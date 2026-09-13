import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/ssh/tunnel_manager.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late Host host;
  late DateTime now;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'pi',
      address: '127.0.0.1',
      port: 22,
      username: 'pi',
    );
    now = DateTime.utc(2026, 9, 13, 12, 0, 0);
  });

  tearDown(() => db.close());

  test('open success writes one open audit; not orphan', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    expect(tunnel.state, TunnelState.listening);

    final audits = await repo.listAudit();
    expect(audits, hasLength(1));
    final open = audits.single;
    expect(open.title, 'Open tunnel → cockpit (9090)');
    expect(open.closeReason, TunnelCloseReason.open.value);
    expect(open.exitCode, isNull);
    expect(open.risk, RiskLevel.read.name);
    expect(open.usedSudo, isFalse);
    expect(
      open.command,
      'ssh -L 127.0.0.1:${tunnel.localPort}:127.0.0.1:9090',
    );
    expect(open.hostId, host.id);
    expect(open.hostAlias, host.alias);
    expect(open.remoteUser, host.username);
    expect(open.orphan, isFalse);
    expect(open.errorSummary, isNull);
  });

  test('close writes one close audit with reason and lifetime durationMs',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    now = now.add(const Duration(seconds: 45));
    await manager.close(tunnel.id, reason: TunnelCloseReason.user);

    final audits = await repo.listAudit();
    expect(audits, hasLength(2));
    final open = audits.singleWhere(
      (e) => e.closeReason == TunnelCloseReason.open.value,
    );
    final close = audits.singleWhere(
      (e) => e.closeReason == TunnelCloseReason.user.value,
    );
    expect(close.title, 'Close tunnel → cockpit (9090) [user]');
    expect(close.exitCode, isNull);
    expect(close.durationMs, 45000);
    expect(close.risk, RiskLevel.read.name);
    expect(close.usedSudo, isFalse);
    expect(
      close.command,
      'ssh -L 127.0.0.1:${tunnel.localPort}:127.0.0.1:9090',
    );
    expect(close.orphan, isFalse);
    expect(open.orphan, isFalse);
  });

  test('channel accepts do not write extra audit events', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    expect(await repo.listAudit(), hasLength(1));

    final a = await Socket.connect('127.0.0.1', tunnel.localPort);
    final b = await Socket.connect('127.0.0.1', tunnel.localPort);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).openChannels,
      2,
    );
    expect(await repo.listAudit(), hasLength(1));

    await a.close();
    await b.close();
    await manager.close(tunnel.id);
    expect(await repo.listAudit(), hasLength(2));
  });

  test('failed open writes errorSummary + closeReason failed; not orphan',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      bind: () async {
        throw const SocketException('bind denied');
      },
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    expect(tunnel.state, TunnelState.failed);

    final audits = await repo.listAudit();
    expect(audits, hasLength(1));
    final row = audits.single;
    expect(row.closeReason, TunnelCloseReason.failed.value);
    expect(row.errorSummary, isNotNull);
    expect(row.errorSummary, isNotEmpty);
    expect(row.exitCode, isNull);
    expect(row.orphan, isFalse);
    expect(row.risk, RiskLevel.read.name);
    expect(row.title, contains('cockpit'));
    expect(row.title, contains('9090'));
  });

  test('SSH drop after open writes open + failed close audits', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    expect(tunnel.state, TunnelState.listening);
    expect(await repo.listAudit(), hasLength(1));

    now = now.add(const Duration(seconds: 12));
    await pool.lastClient!.close();

    ActiveTunnel? failed;
    for (var i = 0; i < 40; i++) {
      failed = manager.current.cast<ActiveTunnel?>().firstWhere(
            (t) => t?.id == tunnel.id,
            orElse: () => null,
          );
      if (failed?.state == TunnelState.failed) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(failed?.state, TunnelState.failed);

    final audits = await repo.listAudit();
    expect(audits, hasLength(2));
    final close = audits.singleWhere(
      (e) => e.closeReason == TunnelCloseReason.failed.value,
    );
    expect(close.errorSummary, isNotNull);
    expect(close.errorSummary, isNotEmpty);
    expect(close.title, 'Close tunnel → cockpit (9090) [failed]');
    expect(close.durationMs, 12000);
    expect(close.exitCode, isNull);
    expect(close.orphan, isFalse);
  });

  test('close still shuts down when recordAudit throws', () async {
    final hosts = _ThrowingAuditHosts(db);
    final pool = _TunnelStubPool(repository: hosts);
    final manager = TunnelManager(
      pool: pool,
      hosts: hosts,
      clock: () => now,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    hosts.throwOnCloseAudit = false;
    final tunnel = await manager.open(
      _target(host.id),
      hostAlias: host.alias,
    );
    expect(tunnel.state, TunnelState.listening);
    expect(manager.debugListenerCount, 1);
    expect(pool.debugTunnelClientCount(host.id), 1);

    hosts.throwOnCloseAudit = true;
    await manager.close(tunnel.id);

    expect(manager.debugListenerCount, 0);
    expect(manager.current.where((t) => t.id == tunnel.id), isEmpty);
    expect(pool.debugTunnelClientCount(host.id), 0);
    await expectLater(
      Socket.connect(
        '127.0.0.1',
        tunnel.localPort,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<SocketException>()),
    );
  });
}

class _ThrowingAuditHosts extends HostRepository {
  _ThrowingAuditHosts(super.db);

  bool throwOnCloseAudit = false;

  @override
  Future<void> recordAudit({
    required String hostId,
    required String hostAlias,
    required String remoteUser,
    required String command,
    required String risk,
    required bool usedSudo,
    String title = '',
    int? exitCode,
    int durationMs = 0,
    String? errorSummary,
    String? closeReason,
  }) {
    if (throwOnCloseAudit &&
        closeReason != null &&
        closeReason != TunnelCloseReason.open.value) {
      throw StateError('audit boom');
    }
    return super.recordAudit(
      hostId: hostId,
      hostAlias: hostAlias,
      remoteUser: remoteUser,
      command: command,
      risk: risk,
      usedSudo: usedSudo,
      title: title,
      exitCode: exitCode,
      durationMs: durationMs,
      errorSummary: errorSummary,
      closeReason: closeReason,
    );
  }
}

TunnelTarget _target(String hostId, {String label = 'cockpit'}) {
  return TunnelTarget(
    id: 'target-$label',
    hostId: hostId,
    label: label,
    remoteHost: '127.0.0.1',
    remotePort: 9090,
    scheme: TunnelScheme.https,
    path: '/',
  );
}

Future<SSHSocket> _holdOpenChannel({
  required SSHClient client,
  required String remoteHost,
  required int remotePort,
}) async {
  return _PipeSocket();
}

class _PipeSocket implements SSHSocket {
  final _incoming = StreamController<Uint8List>();
  final _outgoing = StreamController<List<int>>();
  final _done = Completer<void>();

  _PipeSocket() {
    _outgoing.stream.listen((_) {}, onDone: destroy, onError: (_) => destroy());
  }

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => _outgoing.sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    destroy();
  }

  @override
  void destroy() {
    if (!_incoming.isClosed) _incoming.close();
    if (!_outgoing.isClosed) _outgoing.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> flush() async {}
}

class _TunnelStubPool extends SshSessionPool {
  _TunnelStubPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  SSHClient? lastClient;

  @override
  Future<SSHSocket> connectSocket(
    Host host,
    Set<String> visiting, {
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    return _DummySocket();
  }

  @override
  Future<SSHClient> createAndAuthenticateClient({
    required SSHSocket socket,
    required String username,
    required List<SSHIdentity>? identities,
    required Future<bool> Function(String type, Uint8List fingerprint)
        onVerifyHostKey,
    FutureOr<String?> Function()? onPasswordRequest,
  }) async {
    final client = SSHClient(
      socket,
      username: username,
      identities: identities,
      keepAliveInterval: const Duration(seconds: 30),
      onVerifyHostKey: onVerifyHostKey,
      onPasswordRequest: onPasswordRequest,
    );
    lastClient = client;
    return client;
  }
}

class _DummySocket implements SSHSocket {
  final _controller = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get stream => _controller.stream;

  @override
  StreamSink<List<int>> get sink => _controller.sink;

  @override
  Future<void> get done => _controller.done;

  @override
  Future<void> close() async {
    await _controller.close();
  }

  @override
  void destroy() {
    _controller.close();
  }

  @override
  Future<void> flush() async {}
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('tunnel audit test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('tunnel audit test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('tunnel audit test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
