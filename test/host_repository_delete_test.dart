import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';

void main() {
  test('delete removes facts and recents, keeps the hardware key', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendr',
    );
    await repo.touchRecent(host);
    await repo.setLastHost(host.id);
    await repo.delete(host.id);

    expect(await repo.list(), isEmpty);
    expect(await repo.recentHosts(), isEmpty);
    expect(await repo.lastHostId(), isNull);
    expect(await repo.get(host.id), isNull);
  });
}
