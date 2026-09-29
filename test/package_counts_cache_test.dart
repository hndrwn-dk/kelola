import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  test('package list counts patch fleet cache without wiping load', () async {
    final host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.2',
      port: 22,
      username: 'hendr',
    );
    await repo.saveFleetCache(
      FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: 1.25,
        diskRootPercent: 40,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 9, 28, 7),
      ),
    );

    const snap = PackageSnapshot(
      manager: PackageManager.apt,
      updates: [
        PackageUpdate(name: 'openssl', security: true),
        PackageUpdate(name: 'curl'),
        PackageUpdate(name: 'tzdata'),
      ],
      rebootRequired: false,
    );
    await repo.savePackageUpdateCounts(
      hostId: host.id,
      alias: host.alias,
      snapshot: snap,
    );

    final cached = (await repo.loadFleetCacheByHost())[host.id]!;
    expect(cached.load1, 1.25);
    expect(cached.pendingUpdates, 3);
    expect(cached.securityUpdates, 1);
  });
}
