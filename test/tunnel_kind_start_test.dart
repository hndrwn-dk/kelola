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
import 'package:kelola/domain/facts/host_facts.dart';
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

  test('dynamic start uses SOCKS inject and never binds a local HTTP server',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    var bound = false;
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () {
        bound = true;
        throw StateError('dynamic must not bind');
      },
      startDynamic: (_) async => 1080,
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      TunnelTarget(
        id: 'socks',
        hostId: host.id,
        label: 'Proxy',
        remoteHost: '',
        remotePort: 0,
        scheme: TunnelScheme.http,
        path: '',
        kind: TunnelKind.dynamic,
      ),
      hostAlias: host.alias,
    );

    expect(bound, isFalse);
    expect(tunnel.state, TunnelState.listening);
    expect(tunnel.localPort, 1080);

    final audit = (await repo.listAudit()).single;
    expect(audit.title, 'Open SOCKS5 → Proxy');
    expect(audit.command, 'ssh -D 127.0.0.1:1080');
    expect(audit.closeReason, TunnelCloseReason.open.value);
  });

  test('remote start listens on the host loopback and skips local bind',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    var bound = false;
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      bind: () {
        bound = true;
        throw StateError('remote must not bind');
      },
      startRemote: ({required client, required target}) async {
        return TunnelRemoteStart(
          listenPort: 22000,
          connections: const Stream.empty(),
          close: () async {},
        );
      },
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      TunnelTarget(
        id: 'r1',
        hostId: host.id,
        label: 'ssh-in',
        remoteHost: '127.0.0.1',
        remotePort: 22,
        scheme: TunnelScheme.http,
        path: '',
        kind: TunnelKind.remote,
      ),
      hostAlias: host.alias,
    );

    expect(bound, isFalse);
    expect(tunnel.state, TunnelState.listening);
    expect(tunnel.localPort, 22000);
    expect(
      (await repo.listAudit()).single.command,
      'ssh -R 127.0.0.1:22000:127.0.0.1:22',
    );
  });

  test('kubectl start rediscovers facts then binds a local forward to host port',
      () async {
    final pool = _TunnelStubPool(repository: repo);
    Host? discovered;
    final manager = TunnelManager(
      pool: pool,
      hosts: repo,
      discoverFacts: (h) async {
        discovered = h;
        return HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);
      },
      startKubectl: ({required client, required target, required facts}) async {
        expect(target.remoteHost, 'svc/nginx');
        expect(facts.runtimes, contains('kubectl'));
        return TunnelKubectlStart(hostPort: 34567, stop: () async {});
      },
    );
    addTearDown(manager.dispose);

    final tunnel = await manager.open(
      TunnelTarget(
        id: 'k1',
        hostId: host.id,
        label: 'nginx',
        remoteHost: 'svc/nginx',
        remotePort: 80,
        scheme: TunnelScheme.http,
        path: 'default',
        kind: TunnelKind.kubectl,
      ),
      hostAlias: host.alias,
    );

    expect(discovered?.id, host.id);
    expect(tunnel.state, TunnelState.listening);
    expect(tunnel.localPort, greaterThan(0));
    expect(
      (await repo.listAudit()).single.command,
      contains('port-forward --address 127.0.0.1'),
    );
  });

  test('tunnel manager default path uses dartssh2 loopback APIs', () {
    final src = File('lib/data/ssh/tunnel_manager.dart').readAsStringSync();
    expect(src, contains('forwardDynamic'));
    expect(src, contains("bindHost: '127.0.0.1'"));
    expect(src, contains('forwardRemote'));
    expect(src, contains("host: 'localhost'"));
    expect(src, contains('port-forward'));
    expect(src, isNot(contains('0.0.0.0')));
    expect(src, isNot(contains('command -v')));
  });
}

class _TunnelStubPool extends SshSessionPool {
  _TunnelStubPool({required HostRepository repository})
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
    throw StateError('kind start test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('kind start test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('kind start test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
