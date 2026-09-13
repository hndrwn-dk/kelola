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
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/domain/tunnels/tunnel_close_reason.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'pi',
      address: '127.0.0.1',
      port: 22,
      username: 'pi',
    );
  });

  tearDown(() => db.close());

  test('tunnel_manager.dart has no lifecycle imports or hooks', () {
    final src = File('lib/data/ssh/tunnel_manager.dart').readAsStringSync();
    expect(src.contains('WidgetsBindingObserver'), isFalse);
    expect(src.contains('AppLifecycleState'), isFalse);
    expect(src.contains('onAppBackgrounded'), isFalse);
    expect(src.contains('WidgetsBinding'), isFalse);
  });

  test('idle arms closesAtUtc; idleClosing one minute before; closes with idle',
      () async {
    var now = DateTime.utc(2026, 9, 13, 12, 0, 0);
    final pool = _StubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      idleMinutes: () => 2,
      idlePollInterval: const Duration(milliseconds: 50),
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.listening);
    expect(tunnel.openChannels, 0);
    expect(tunnel.closesAtUtc, isNotNull);
    expect(
      tunnel.closesAtUtc,
      now.add(const Duration(minutes: 2)),
    );

    // Still listening before the warn window.
    now = now.add(const Duration(minutes: 1) - const Duration(milliseconds: 1));
    await _pumpIdle();
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).state,
      TunnelState.listening,
    );
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).closesAtUtc,
      isNotNull,
    );

    // One minute before deadline → idleClosing; countdown field still present.
    now = tunnel.closesAtUtc!.subtract(const Duration(minutes: 1));
    await _pumpIdle();
    final warning = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(warning.state, TunnelState.idleClosing);
    expect(warning.closesAtUtc, tunnel.closesAtUtc);

    now = tunnel.closesAtUtc!;
    await _pumpIdle();

    expect(manager.current.where((t) => t.id == tunnel.id), isEmpty);
    expect(manager.debugCloseReason(tunnel.id), TunnelCloseReason.idle);
    expect(manager.debugListenerCount, 0);
  });

  test('accept resets idle timer and clears closesAtUtc while busy', () async {
    var now = DateTime.utc(2026, 9, 13, 15, 0, 0);
    final pool = _StubPool(repository: repo);
    final remotes = <_PipeSocket>[];
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      idleMinutes: () => 2,
      idlePollInterval: const Duration(milliseconds: 50),
      openChannel: ({
        required SSHClient client,
        required String remoteHost,
        required int remotePort,
      }) async {
        final remote = _PipeSocket();
        remotes.add(remote);
        return remote;
      },
    );
    addTearDown(() async {
      for (final r in remotes) {
        r.destroy();
      }
      await manager.dispose();
    });

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    final firstDeadline = tunnel.closesAtUtc!;
    expect(firstDeadline, now.add(const Duration(minutes: 2)));

    final probe = await Socket.connect('127.0.0.1', tunnel.localPort);
    addTearDown(() async {
      try {
        await probe.close();
      } catch (_) {}
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _pumpIdle();

    final busy = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(busy.openChannels, 1);
    expect(busy.closesAtUtc, isNull);
    expect(busy.state, TunnelState.listening);

    // Jump deep into what would have been the first idle window.
    now = firstDeadline.add(const Duration(minutes: 30));
    await _pumpIdle();
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).state,
      TunnelState.listening,
    );
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).closesAtUtc,
      isNull,
    );

    remotes.single.destroy();
    await probe.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _pumpIdle();

    final rearmed = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(rearmed.openChannels, 0);
    expect(rearmed.closesAtUtc, isNotNull);
    expect(rearmed.closesAtUtc, now.add(const Duration(minutes: 2)));
    expect(rearmed.closesAtUtc!.isAfter(firstDeadline), isTrue);
    expect(rearmed.state, TunnelState.listening);
  });

  test('accept during idleClosing returns to listening and rearms later', () async {
    var now = DateTime.utc(2026, 9, 13, 18, 0, 0);
    final pool = _StubPool(repository: repo);
    final remotes = <_PipeSocket>[];
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      clock: () => now,
      idleMinutes: () => 2,
      idlePollInterval: const Duration(milliseconds: 50),
      openChannel: ({
        required SSHClient client,
        required String remoteHost,
        required int remotePort,
      }) async {
        final remote = _PipeSocket();
        remotes.add(remote);
        return remote;
      },
    );
    addTearDown(() async {
      for (final r in remotes) {
        r.destroy();
      }
      await manager.dispose();
    });

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    final deadline = tunnel.closesAtUtc!;

    now = deadline.subtract(const Duration(minutes: 1));
    await _pumpIdle();
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).state,
      TunnelState.idleClosing,
    );

    final probe = await Socket.connect('127.0.0.1', tunnel.localPort);
    addTearDown(() async {
      try {
        await probe.close();
      } catch (_) {}
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _pumpIdle();

    final active = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(active.state, TunnelState.listening);
    expect(active.closesAtUtc, isNull);
    expect(active.openChannels, 1);

    remotes.single.destroy();
    await probe.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _pumpIdle();

    final after = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(after.state, TunnelState.listening);
    expect(after.closesAtUtc, now.add(const Duration(minutes: 2)));
  });
}

/// Idle poll uses a short interval; advance wall time slightly so the tick runs.
Future<void> _pumpIdle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

TunnelTarget _target(String hostId) {
  return TunnelTarget(
    id: 'target-cockpit',
    hostId: hostId,
    label: 'cockpit',
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
  bool isDestroyed = false;

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
    isDestroyed = true;
    if (!_incoming.isClosed) _incoming.close();
    if (!_outgoing.isClosed) _outgoing.close();
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> flush() async {}
}

class _StubPool extends SshSessionPool {
  _StubPool({required HostRepository repository})
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
    throw StateError('idle timeout test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('idle timeout test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('idle timeout test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
