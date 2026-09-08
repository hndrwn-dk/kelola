import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';

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

  test('normal execute path constructs client without onPasswordRequest', () async {
    final pool = _RecordingPool(repository: repo);
    await expectLater(
      pool.execute(host, const HostFactsProbe()),
      throwsA(isA<_StopBeforeSocket>()),
    );
    expect(pool.openUsedPassword, [false]);
    expect(pool.lastOpenUsedPassword, isFalse);
  });

  test('runPasswordBootstrap constructs client with onPasswordRequest', () async {
    final pool = _RecordingPool(repository: repo);
    final password = EphemeralPassword()..set('secret');
    await expectLater(
      pool.runPasswordBootstrap(
        host: host,
        password: password,
        onUnknownHostKey: (_, __, ___) async => true,
        body: (_) async {},
      ),
      throwsA(isA<_StopBeforeSocket>()),
    );
    expect(pool.openUsedPassword, [true]);
    expect(pool.lastOpenUsedPassword, isTrue);
    expect(pool.disconnectCalls, contains(host.id));
  });

  test('verifyFreshKeyAuth disconnects then opens key-only client', () async {
    final pool = _RecordingPool(repository: repo);
    pool.lastOpenUsedPassword = true;
    await expectLater(
      pool.verifyFreshKeyAuth(host, const HostFactsProbe()),
      throwsA(isA<_StopBeforeSocket>()),
    );
    expect(pool.openUsedPassword, [false]);
    expect(pool.lastOpenUsedPassword, isFalse);
    expect(pool.disconnectCalls, contains(host.id));
  });

  test('password request waits for host-key accept before reading password', () async {
    final gate = Completer<bool>();
    final password = EphemeralPassword()..set('secret');
    final handler = gatedPasswordRequest(
      hostKeyAccepted: gate,
      onPasswordRequest: password.read,
    );
    final pending = Future.sync(handler);
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await pumpEventQueue();
    expect(completed, isFalse);

    gate.complete(true);
    expect(await pending, 'secret');
    expect(completed, isTrue);
  });

  test('password request returns null when host-key verify rejects', () async {
    final gate = Completer<bool>();
    final password = EphemeralPassword()..set('secret');
    final handler = gatedPasswordRequest(
      hostKeyAccepted: gate,
      onPasswordRequest: password.read,
    );
    final pending = Future.sync(handler);
    gate.complete(false);
    expect(await pending, isNull);
  });

  test('password bootstrap open does not insert client into the pool', () async {
    final pool = _StubAuthPool(repository: repo);
    final client = await pool.openPasswordBootstrap(
      host,
      onPasswordRequest: () => 'secret',
      onUnknownHostKey: (_, __, ___) async => true,
    );
    expect(pool.debugPooledCount(host.id), 0);
    expect(pool.hasLiveSession(host.id), isFalse);
    expect(client.isClosed, isTrue);
  });

  test('openSession surfaces HostKeyMismatchException on changed pin', () async {
    await repo.pinKey(
      hostId: host.id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'pinned-fp',
    );
    final pool = _MismatchAbortPool(repository: repo);
    await expectLater(
      pool.openPasswordBootstrap(
        host,
        onPasswordRequest: () => 'secret',
      ),
      throwsA(
        isA<HostKeyMismatchException>()
            .having((e) => e.pinnedFingerprint, 'pinned', 'pinned-fp')
            .having((e) => e.seenFingerprint, 'seen', 'seen-fp'),
      ),
    );
  });

  test('openSession gate: password waits until host-key accept', () async {
    final pool = _GateDrivePool(repository: repo, acceptHostKey: true);
    final password = EphemeralPassword()..set('secret');
    await expectLater(
      pool.openPasswordBootstrap(
        host,
        onPasswordRequest: password.read,
        onUnknownHostKey: (_, __, ___) async => true,
      ),
      throwsA(isA<_StopAfterGateDrive>()),
    );
    expect(pool.passwordReturnedBeforeVerify, isFalse);
    expect(pool.passwordResult, 'secret');
  });

  test('openSession gate: password is null when host-key rejects', () async {
    final pool = _GateDrivePool(repository: repo, acceptHostKey: false);
    final password = EphemeralPassword()..set('secret');
    await expectLater(
      pool.openPasswordBootstrap(
        host,
        onPasswordRequest: password.read,
        onUnknownHostKey: (_, __, ___) async => false,
      ),
      throwsA(isA<_StopAfterGateDrive>()),
    );
    expect(pool.passwordReturnedBeforeVerify, isFalse);
    expect(pool.passwordResult, isNull);
  });
}

class _StopBeforeSocket implements Exception {
  const _StopBeforeSocket();
}

class _StopAfterGateDrive implements Exception {
  const _StopAfterGateDrive();
}

/// Records password vs key-only opens without needing a real SSH socket.
class _RecordingPool extends SshSessionPool {
  _RecordingPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  final openUsedPassword = <bool>[];
  final disconnectCalls = <String>[];

  @override
  void noteClientOpen({required bool usedPassword}) {
    openUsedPassword.add(usedPassword);
    super.noteClientOpen(usedPassword: usedPassword);
  }

  @override
  Future<SSHSocket> connectSocket(
    Host host,
    Set<String> visiting, {
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    throw const _StopBeforeSocket();
  }

  @override
  Future<void> disconnect(String hostId) async {
    disconnectCalls.add(hostId);
    await super.disconnect(hostId);
  }
}

/// Completes open without a real handshake so pool membership can be asserted.
class _StubAuthPool extends SshSessionPool {
  _StubAuthPool({required HostRepository repository})
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
    final client = SSHClient(socket, username: username);
    await client.close();
    return client;
  }
}

/// Runs real openSession verify, then aborts like dartssh2 on host-key reject.
class _MismatchAbortPool extends SshSessionPool {
  _MismatchAbortPool({required HostRepository repository})
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
    final accepted = await onVerifyHostKey(
      'ssh-ed25519',
      Uint8List.fromList(utf8.encode('seen-fp')),
    );
    expect(accepted, isFalse);
    throw SSHAuthAbortError('host key rejected');
  }
}

/// Drives password vs host-key ordering through openSession's real gate wiring.
class _GateDrivePool extends SshSessionPool {
  _GateDrivePool({
    required HostRepository repository,
    required this.acceptHostKey,
  }) : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  final bool acceptHostKey;
  bool passwordReturnedBeforeVerify = true;
  String? passwordResult;

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
    expect(onPasswordRequest, isNotNull);
    final pending = Future.sync(onPasswordRequest!);
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await pumpEventQueue();
    passwordReturnedBeforeVerify = completed;

    final accepted = await onVerifyHostKey(
      'ssh-ed25519',
      Uint8List.fromList(utf8.encode('tofu-fp')),
    );
    expect(accepted, acceptHostKey);

    passwordResult = await pending;
    throw const _StopAfterGateDrive();
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
    throw StateError('session pool key-install test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('session pool key-install test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('session pool key-install test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
