import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/domain/exceptions.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late HostKeyPolicy policy;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    policy = HostKeyPolicy(repo);
  });

  tearDown(() => db.close());

  Future<String> hostId() async {
    final host = await repo.insert(
      alias: 'wsl',
      address: '192.168.1.10',
      port: 22,
      username: 'hendr',
    );
    return host.id;
  }

  Uint8List fp(String text) => Uint8List.fromList(utf8.encode(text));

  test('unknown host key asks the handler and does not throw', () async {
    final id = await hostId();
    var asked = false;
    final ok = await policy.verify(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprintBytes: fp('SHA256:abc'),
      onUnknown: (algorithm, seen) async {
        asked = true;
        expect(algorithm, 'ssh-ed25519');
        expect(seen, 'SHA256:abc');
        await repo.pinKey(
          hostId: id,
          algorithm: algorithm,
          fingerprint: seen,
        );
        return true;
      },
    );
    expect(asked, isTrue);
    expect(ok, isTrue);
    expect(policy.takeMismatch(), isNull);
  });

  test('mismatch returns false instead of throwing', () async {
    final id = await hostId();
    await repo.pinKey(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:pinned',
    );
    final ok = await policy.verify(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprintBytes: fp('SHA256:other'),
    );
    expect(ok, isFalse);
    final mismatch = policy.takeMismatch();
    expect(mismatch, isA<HostKeyMismatchException>());
    expect(mismatch!.seenFingerprint, 'SHA256:other');
    expect(mismatch.pinnedFingerprint, 'SHA256:pinned');
  });

  test('matching pin returns true', () async {
    final id = await hostId();
    await repo.pinKey(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:ok',
    );
    final ok = await policy.verify(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprintBytes: fp('SHA256:ok'),
    );
    expect(ok, isTrue);
  });
}
