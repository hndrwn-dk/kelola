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

  test('9th accepted connection is closed immediately; droppedChannels increments',
      () async {
    final pool = _StubPool(repository: repo);
    final held = <_HoldSocket>[];
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      openChannel: ({
        required SSHClient client,
        required String remoteHost,
        required int remotePort,
      }) async {
        final s = _HoldSocket();
        held.add(s);
        return s;
      },
    );
    addTearDown(() async {
      for (final s in held) {
        s.destroy();
      }
      await manager.dispose();
    });

    final tunnel = await manager.open(
      TunnelTarget(
        id: 't1',
        hostId: host.id,
        label: 'grafana',
        remoteHost: '127.0.0.1',
        remotePort: 3000,
        scheme: TunnelScheme.http,
        path: '/',
      ),
      hostAlias: host.alias,
    );
    expect(tunnel.state, TunnelState.listening);

    final sockets = <Socket>[];
    addTearDown(() async {
      for (final s in sockets) {
        try {
          await s.close();
        } catch (_) {}
      }
    });

    for (var i = 0; i < 8; i++) {
      sockets.add(await Socket.connect('127.0.0.1', tunnel.localPort));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(held.length, 8);

    final ninth = await Socket.connect('127.0.0.1', tunnel.localPort);
    sockets.add(ninth);
    // 9th must be accepted then closed by the manager (cap).
    // Prefer draining the stream — Socket.done is flaky on Windows after destroy.
    await ninth.drain<void>().timeout(const Duration(seconds: 2));

    expect(held.length, 8);

    // Debounced channel-count / dropped emission.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final live = manager.current.singleWhere((t) => t.id == tunnel.id);
    expect(live.openChannels, 8);
    expect(live.droppedChannels, 1);

    await manager.close(tunnel.id);
  });
}

class _HoldSocket implements SSHSocket {
  final _incoming = StreamController<Uint8List>();
  final _outgoing = StreamController<List<int>>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _incoming.stream;

  @override
  StreamSink<List<int>> get sink => _outgoing.sink;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async => destroy();

  @override
  void destroy() {
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
    return SSHClient(
      socket,
      username: username,
      identities: identities,
      keepAliveInterval: const Duration(seconds: 30),
      onVerifyHostKey: onVerifyHostKey,
      onPasswordRequest: onPasswordRequest,
    );
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
    throw StateError('channel cap test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('channel cap test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('channel cap test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
