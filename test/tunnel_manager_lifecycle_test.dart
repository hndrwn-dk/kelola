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

  test('createAndAuthenticateClient sets keepAliveInterval to 30s', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(
      src,
      contains('keepAliveInterval: const Duration(seconds: 30)'),
    );
  });

  test('acquireTunnelClient uses createAndAuthenticateClient, not password bootstrap',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    final client = await pool.acquireTunnelClient(host);

    expect(pool.createAuthCalls, 1);
    expect(pool.lastUsedPassword, isFalse);
    expect(pool.lastOnPasswordRequestWasNull, isTrue);
    expect(client.keepAliveInterval, const Duration(seconds: 30));
    expect(pool.lastOpenUsedPassword, isFalse);

    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    final start = src.indexOf('Future<SSHClient> acquireTunnelClient');
    expect(start, greaterThanOrEqualTo(0));
    final end = src.indexOf('\n  Future<', start + 1);
    final body = src.substring(start, end < 0 ? src.length : end);
    expect(body.contains('openPasswordBootstrap'), isFalse);
    expect(body.contains('runPasswordBootstrap'), isFalse);
    expect(
      body.contains('openSession') || body.contains('createAndAuthenticateClient'),
      isTrue,
    );
  });

  test('acquireTunnelClient is separate from the exec pool', () async {
    final pool = _TunnelStubPool(repository: repo);
    await pool.acquireTunnelClient(host);

    expect(pool.debugPooledCount(host.id), 0);
    expect(pool.debugTunnelClientCount(host.id), 1);

    final again = await pool.acquireTunnelClient(host);
    expect(pool.createAuthCalls, 1);
    expect(pool.debugTunnelClientCount(host.id), 1);
    expect(identical(again, pool.lastClient), isTrue);
  });

  test('closeAll closes dedicated tunnel clients', () async {
    final pool = _TunnelStubPool(repository: repo);
    final client = await pool.acquireTunnelClient(host);
    expect(client.isClosed, isFalse);
    expect(pool.debugTunnelClientCount(host.id), 1);

    await pool.closeAll();

    expect(client.isClosed, isTrue);
    expect(pool.debugTunnelClientCount(host.id), 0);
    expect(pool.debugPooledCount(host.id), 0);
  });

  test('open then close leaves zero listeners and zero channels', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.listening);
    expect(tunnel.localPort, isNot(0));
    expect(manager.debugListenerCount, 1);

    final probe = await Socket.connect('127.0.0.1', tunnel.localPort);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).openChannels,
      1,
    );
    await probe.close();
    await Future<void>.delayed(const Duration(milliseconds: 80));

    await manager.close(tunnel.id);
    expect(manager.debugListenerCount, 0);
    expect(manager.current.where((t) => t.id == tunnel.id), isEmpty);
    expect(pool.debugTunnelClientCount(host.id), 0);
    expect(pool.lastClient?.isClosed, isTrue);
    await expectLater(
      Socket.connect(
        '127.0.0.1',
        tunnel.localPort,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<SocketException>()),
    );
  });

  test('last tunnel close releases dedicated tunnel client', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final a = await manager.open(_target(host.id), hostAlias: host.alias);
    final b = await manager.open(
      TunnelTarget(
        id: 'target-grafana',
        hostId: host.id,
        label: 'grafana',
        remoteHost: '127.0.0.1',
        remotePort: 3000,
        scheme: TunnelScheme.http,
        path: '/',
      ),
      hostAlias: host.alias,
    );
    expect(pool.debugTunnelClientCount(host.id), 1);
    expect(pool.createAuthCalls, 1);

    await manager.close(a.id);
    expect(pool.debugTunnelClientCount(host.id), 1);

    await manager.close(b.id);
    expect(pool.debugTunnelClientCount(host.id), 0);
    expect(pool.lastClient?.isClosed, isTrue);
    expect(pool.releaseTunnelClientCalls, greaterThanOrEqualTo(1));
  });

  test('hasLiveSession is true while a tunnel client is held', () async {
    final pool = _TunnelStubPool(repository: repo);
    expect(pool.hasLiveSession(host.id), isFalse);
    await pool.acquireTunnelClient(host);
    expect(pool.hasLiveSession(host.id), isTrue);
    await pool.releaseTunnelClient(host.id);
    expect(pool.hasLiveSession(host.id), isFalse);
  });

  test('slow openChannel + closeAll leaves zero live sockets/channels', () async {
    final pool = _TunnelStubPool(repository: repo);
    final entered = Completer<void>();
    final release = Completer<void>();
    final remotes = <_PipeSocket>[];
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: ({
        required SSHClient client,
        required String remoteHost,
        required int remotePort,
      }) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        final remote = _PipeSocket();
        remotes.add(remote);
        return remote;
      },
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.listening);

    final probe = await Socket.connect('127.0.0.1', tunnel.localPort);
    await entered.future.timeout(const Duration(seconds: 2));
    expect(manager.debugOpeningCount, 1);
    expect(manager.debugLiveChannelCount, 0);

    await manager.closeAll(reason: TunnelCloseReason.termination);
    expect(manager.debugListenerCount, 0);
    expect(manager.current, isEmpty);
    expect(manager.debugOpeningCount, 0);
    expect(manager.debugLiveChannelCount, 0);
    expect(manager.debugInFlightLocalCount, 0);

    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(manager.debugListenerCount, 0);
    expect(manager.current, isEmpty);
    expect(manager.debugOpeningCount, 0);
    expect(manager.debugLiveChannelCount, 0);
    expect(manager.debugInFlightLocalCount, 0);
    expect(remotes, isNotEmpty);
    for (final remote in remotes) {
      expect(remote.isDestroyed, isTrue);
    }
    await expectLater(
      probe.drain<void>().timeout(const Duration(seconds: 2)),
      completes,
    );
  });

  test('failed open sets closeReason failed alongside errorSummary', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () async {
        throw const SocketException('bind denied');
      },
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.failed);
    expect(tunnel.errorSummary, isNotNull);
    expect(manager.debugCloseReason(tunnel.id), TunnelCloseReason.failed);
  });

  test('closeAll closes three tunnels; close is idempotent', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final a = await manager.open(_target(host.id, label: 'a'), hostAlias: 'pi');
    final b = await manager.open(_target(host.id, label: 'b'), hostAlias: 'pi');
    final c = await manager.open(_target(host.id, label: 'c'), hostAlias: 'pi');
    expect(manager.debugListenerCount, 3);

    await manager.closeAll(reason: TunnelCloseReason.termination);
    expect(manager.debugListenerCount, 0);
    expect(manager.current, isEmpty);

    await manager.close(a.id);
    await manager.close(b.id);
    await manager.close(c.id);
    expect(manager.debugListenerCount, 0);
  });

  test('failed bind → failed with no leftover listener', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () async {
        throw const SocketException('bind denied');
      },
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.failed);
    expect(tunnel.errorSummary, isNotNull);
    expect(tunnel.errorSummary, isNotEmpty);
    expect(manager.debugCloseReason(tunnel.id), TunnelCloseReason.failed);
    expect(manager.debugListenerCount, 0);
    expect(
      manager.current.singleWhere((t) => t.id == tunnel.id).state,
      TunnelState.failed,
    );
  });

  test('dropped SSH client → failed with message, not stuck listening', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(tunnel.state, TunnelState.listening);

    final client = pool.lastClient!;
    await client.close();

    ActiveTunnel? failed;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      failed = manager.current.cast<ActiveTunnel?>().firstWhere(
            (t) => t?.id == tunnel.id,
            orElse: () => null,
          );
      if (failed?.state == TunnelState.failed) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(failed, isNotNull);
    expect(failed!.state, TunnelState.failed);
    expect(failed.errorSummary, isNotNull);
    expect(failed.errorSummary, isNotEmpty);
    expect(manager.debugListenerCount, 0);
    await expectLater(
      Socket.connect(
        '127.0.0.1',
        tunnel.localPort,
        timeout: const Duration(milliseconds: 200),
      ),
      throwsA(isA<SocketException>()),
    );
  });

  test('watch emits on open and remove on close; dismissFailed clears failed',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final events = <List<ActiveTunnel>>[];
    final sub = manager.watch().listen(events.add);
    addTearDown(sub.cancel);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.any((t) => t.id == tunnel.id), isTrue);

    await manager.close(tunnel.id);
    await Future<void>.delayed(Duration.zero);
    expect(events.last.any((t) => t.id == tunnel.id), isFalse);

    final failManager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () async => throw const SocketException('nope'),
      openChannel: _holdOpenChannel,
    );
    addTearDown(failManager.dispose);
    final bad = await failManager.open(_target(host.id), hostAlias: 'pi');
    expect(bad.state, TunnelState.failed);
    failManager.dismissFailed(bad.id);
    expect(failManager.current.where((t) => t.id == bad.id), isEmpty);
  });

  test('retry reopens a failed tunnel from the same target', () async {
    var bindCalls = 0;
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () async {
        bindCalls++;
        if (bindCalls == 1) {
          throw const SocketException('first bind fails');
        }
        return bindLoopbackEphemeral();
      },
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final failed = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(failed.state, TunnelState.failed);

    final retried = await manager.retry(failed.id);
    expect(retried.state, TunnelState.listening);
    expect(retried.localPort, isNot(0));
    expect(manager.debugListenerCount, 1);
    await manager.close(retried.id);
  });

  test('tunnel_manager.dart has no entitlement or WidgetsBinding imports', () {
    final src = File('lib/data/ssh/tunnel_manager.dart').readAsStringSync();
    expect(src.contains('entitlement'), isFalse);
    expect(src.contains('WidgetsBinding'), isFalse);
    expect(src.contains('AppLifecycleState'), isFalse);
  });

  test('closing last tunnel releases dedicated tunnel client', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final a = await manager.open(_target(host.id), hostAlias: host.alias);
    final b = await manager.open(
      _target(host.id, label: 'grafana'),
      hostAlias: host.alias,
    );
    expect(pool.debugTunnelClientCount(host.id), 1);

    await manager.close(a.id);
    expect(pool.debugTunnelClientCount(host.id), 1);

    await manager.close(b.id);
    expect(pool.debugTunnelClientCount(host.id), 0);
    expect(pool.lastClient!.isClosed, isTrue);
  });

  test('failed tunnel releases dedicated tunnel client', () async {
    final pool = _TunnelStubPool(repository: repo);
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: _holdOpenChannel,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(_target(host.id), hostAlias: host.alias);
    expect(pool.debugTunnelClientCount(host.id), 1);

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
    expect(pool.debugTunnelClientCount(host.id), 0);
  });
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

/// In-memory SSHSocket that stays open until closed (for accept/pipe tests).
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

/// Stubs socket + auth; mirrors production keepalive on the shared factory path.
class _TunnelStubPool extends SshSessionPool {
  _TunnelStubPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  int createAuthCalls = 0;
  int releaseTunnelClientCalls = 0;
  bool? lastUsedPassword;
  bool? lastOnPasswordRequestWasNull;
  SSHClient? lastClient;

  @override
  Future<void> releaseTunnelClient(String hostId) async {
    releaseTunnelClientCalls++;
    await super.releaseTunnelClient(hostId);
  }

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
    createAuthCalls++;
    lastUsedPassword = onPasswordRequest != null;
    lastOnPasswordRequestWasNull = onPasswordRequest == null;
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
    throw StateError('tunnel lifecycle test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('tunnel lifecycle test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('tunnel lifecycle test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
