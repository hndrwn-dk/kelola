import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';

void main() {
  test('save and load package list cache round-trips snapshot', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.2',
      port: 22,
      username: 'hendr',
    );
    const snap = PackageSnapshot(
      manager: PackageManager.apt,
      updates: [PackageUpdate(name: 'curl', security: false)],
      rebootRequired: false,
    );
    expect(await repo.loadPackageListCache(host.id), isNull);
    await repo.savePackageListCache(hostId: host.id, snapshot: snap);
    final loaded = await repo.loadPackageListCache(host.id);
    expect(loaded, isNotNull);
    expect(loaded!.snapshot.updates.single.name, 'curl');
    expect(loaded.snapshot.manager, PackageManager.apt);
    expect(
      DateTime.now().toUtc().difference(loaded.fetchedAt).inMinutes,
      lessThan(2),
    );
  });

  test('delete host clears package list cache', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.2',
      port: 22,
      username: 'hendr',
    );
    await repo.savePackageListCache(
      hostId: host.id,
      snapshot: const PackageSnapshot(
        manager: PackageManager.apt,
        updates: [],
        rebootRequired: false,
      ),
    );
    await repo.delete(host.id);
    expect(await repo.loadPackageListCache(host.id), isNull);
  });
}
