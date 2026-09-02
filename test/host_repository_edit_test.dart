import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/domain/hosts/host_edit.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  Future<String> seed({
    String alias = 'nas-01',
    String address = '192.168.1.24',
    int port = 22,
    String username = 'hendra',
    String? jumpHostId,
  }) async {
    final host = await repo.insert(
      alias: alias,
      address: address,
      port: port,
      username: username,
      jumpHostId: jumpHostId,
    );
    await repo.pinKey(
      hostId: host.id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:pinned',
    );
    return host.id;
  }

  test('changing address clears the pinned host key and does not reuse it',
      () async {
    final id = await seed();
    expect(await repo.pinnedKey(id), isNotNull);

    final result = await repo.updateHost(id, address: '10.0.0.9');

    expect(result.pinReset, isTrue);
    expect(result.disconnectSession, isTrue);
    expect(await repo.pinnedKey(id), isNull);
    expect((await repo.get(id))!.address, '10.0.0.9');

    final policy = HostKeyPolicy(repo);
    var askedTofu = false;
    final ok = await policy.verify(
      hostId: id,
      algorithm: 'ssh-ed25519',
      fingerprintBytes: Uint8List.fromList(utf8.encode('SHA256:pinned')),
      onUnknown: (algorithm, seen) async {
        askedTofu = true;
        expect(seen, 'SHA256:pinned');
        return false;
      },
    );
    expect(askedTofu, isTrue, reason: 'cleared pin must go through TOFU');
    expect(ok, isFalse, reason: 'must not auto-trust after address change');
  });

  test('same address does not clear the pin', () async {
    final id = await seed();
    final result = await repo.updateHost(id, address: '192.168.1.24');
    expect(result.pinReset, isFalse);
    expect(await repo.pinnedKey(id), isNotNull);
  });

  test('username change keeps the pinned host key and still disconnects',
      () async {
    final id = await seed();
    final result = await repo.updateHost(id, username: 'ops');
    expect(result.pinReset, isFalse);
    expect(result.disconnectSession, isTrue);
    expect(await repo.pinnedKey(id), isNotNull);
    expect((await repo.get(id))!.username, 'ops');
  });

  test('port and jump changes keep the pin and disconnect the session',
      () async {
    final jump = await repo.insert(
      alias: 'bastion',
      address: '10.0.0.1',
      port: 22,
      username: 'hendra',
    );
    final id = await seed();
    final portResult = await repo.updateHost(id, port: 2222);
    expect(portResult.pinReset, isFalse);
    expect(portResult.disconnectSession, isTrue);
    expect(await repo.pinnedKey(id), isNotNull);
    expect((await repo.get(id))!.port, 2222);

    final jumpResult = await repo.updateHost(id, jumpHostId: jump.id);
    expect(jumpResult.pinReset, isFalse);
    expect(jumpResult.disconnectSession, isTrue);
    expect((await repo.get(id))!.jumpHostId, jump.id);
  });

  test('alias rename keeps the pin and does not drop the session', () async {
    final id = await seed();
    final result = await repo.updateHost(id, alias: 'files');
    expect(result.pinReset, isFalse);
    expect(result.disconnectSession, isFalse);
    expect(await repo.pinnedKey(id), isNotNull);
    expect((await repo.get(id))!.alias, 'files');
  });

  test('updateHost writes human audit titles, not LC_ALL=C', () async {
    final jump = await repo.insert(
      alias: 'bastion',
      address: '10.0.0.1',
      port: 22,
      username: 'hendra',
    );
    final id = await seed();

    await repo.updateHost(id, alias: 'files');
    await repo.updateHost(id, port: 2222);
    await repo.updateHost(id, jumpHostId: jump.id);
    await repo.updateHost(id, username: 'ops');
    await repo.updateHost(id, address: '10.0.0.9');
    await repo.setReadOnly(id, true);
    await repo.setReadOnly(id, false);

    final titles = (await repo.listAudit(hostId: id)).map((e) => e.title).toList();
    expect(titles, contains(HostEditAudit.renamed('files')));
    expect(titles, contains(HostEditAudit.changedPort));
    expect(titles, contains(HostEditAudit.changedJump('bastion')));
    expect(titles, contains(HostEditAudit.changedUsername('ops')));
    expect(titles, contains(HostEditAudit.changedAddress));
    expect(titles, contains(HostEditAudit.setReadOnly));
    expect(titles, contains(HostEditAudit.allowedWrites));
    for (final row in await repo.listAudit(hostId: id)) {
      expect(row.title.toLowerCase(), isNot(contains('lc_all')));
      expect(row.command.toLowerCase(), isNot(contains('lc_all')));
    }
  });
}
