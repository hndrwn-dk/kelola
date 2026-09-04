import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

void main() {
  test('host tags are multi-value and filterable', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final a = await repo.insert(
      alias: 'web',
      address: '10.0.0.1',
      port: 22,
      username: 'u',
    );
    final b = await repo.insert(
      alias: 'db',
      address: '10.0.0.2',
      port: 22,
      username: 'u',
    );
    await repo.setHostTags(a.id, ['prod', 'client-a']);
    await repo.setHostTags(b.id, ['staging']);

    final hosts = await repo.list();
    final web = hosts.firstWhere((h) => h.id == a.id);
    expect(web.tags, ['client-a', 'prod']);

    final health = [
      FleetHostHealth(
        hostId: a.id,
        alias: 'web',
        reachable: true,
        load1: 0.1,
        diskRootPercent: 10,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: b.id,
        alias: 'db',
        reachable: true,
        load1: 0.1,
        diskRootPercent: 10,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    ];
    final tagsByHost = {for (final h in hosts) h.id: h.tags};
    final filtered = filterFleetByTag(health, tagsByHost, 'prod');
    expect(filtered.map((h) => h.alias), ['web']);
  });

  test('fleet cache round-trips with age marker', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final h = await repo.insert(
      alias: 'nas',
      address: '10.0.0.3',
      port: 22,
      username: 'u',
    );
    final at = DateTime.utc(2026, 1, 1, 12);
    await repo.saveFleetCache(
      FleetHostHealth(
        hostId: h.id,
        alias: 'nas',
        reachable: true,
        load1: 1.5,
        diskRootPercent: 80,
        failedUnitCount: 1,
        pendingUpdates: 3,
        fetchedAt: at,
      ),
    );
    final cache = await repo.loadFleetCacheByHost();
    expect(cache[h.id]!.fromCache, isTrue);
    expect(cache[h.id]!.pendingUpdates, 3);
    expect(cache[h.id]!.isStale(now: DateTime.utc(2026, 1, 1, 13)), isTrue);
    expect(cache[h.id]!.tileSummary(now: DateTime.utc(2026, 1, 1, 13)), contains('cache'));
  });
}
