import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/fleet/fleet_watch_runner.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  Future<Host> seed() {
    return repo.insert(
      alias: 'web-01',
      address: '10.0.0.1',
      port: 22,
      username: 'ops',
    );
  }

  FleetHostHealth health(Host host, {int failed = 0}) {
    return FleetHostHealth(
      hostId: host.id,
      alias: host.alias,
      reachable: true,
      load1: 0.1,
      nprocCores: 2,
      memPercent: 20,
      diskRootPercent: 10,
      failedUnitCount: failed,
      pendingUpdates: 0,
      fetchedAt: DateTime.utc(2026, 9, 27, 12),
    );
  }

  test('first tick is baseline; second tick notifies a new failed-unit state',
      () async {
    final host = await seed();
    final runner = FleetWatchRunner(hosts: repo);
    final first = await runner.tick(
      hosts: [host],
      thresholds: FleetWatchThresholds.defaults,
      now: DateTime.utc(2026, 9, 27, 12),
      probe: (_) async => health(host, failed: 2),
    );
    expect(first, isEmpty);

    final second = await runner.tick(
      hosts: [host],
      thresholds: FleetWatchThresholds.defaults,
      now: DateTime.utc(2026, 9, 27, 13),
      probe: (_) async => health(host, failed: 2),
    );
    expect(second, isEmpty);

    final third = await runner.tick(
      hosts: [host],
      thresholds: FleetWatchThresholds.defaults,
      now: DateTime.utc(2026, 9, 27, 14),
      probe: (_) async => health(host),
    );
    expect(third, hasLength(1));
    expect(third.single.alias, 'web-01');
    expect(third.single.body, 'recovered');
  });

  test('tick refuses to invent hosts outside the supplied list', () async {
    final host = await seed();
    final other = await repo.insert(
      alias: 'db-02',
      address: '10.0.0.2',
      port: 22,
      username: 'ops',
    );
    var probed = <String>[];
    final runner = FleetWatchRunner(hosts: repo);
    await runner.tick(
      hosts: [host],
      thresholds: FleetWatchThresholds.defaults,
      now: DateTime.utc(2026, 9, 27, 12),
      probe: (h) async {
        probed.add(h.id);
        return health(h);
      },
    );
    expect(probed, [host.id]);
    expect(probed, isNot(contains(other.id)));
  });

  test('probe failure keeps previously cached package counts', () async {
    final host = await seed();
    await repo.saveFleetCache(
      FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: 0.2,
        failedUnitCount: 0,
        pendingUpdates: 7,
        securityUpdates: 2,
        fetchedAt: DateTime.utc(2026, 9, 27, 11),
      ),
    );
    final runner = FleetWatchRunner(hosts: repo);
    await runner.tick(
      hosts: [host],
      thresholds: FleetWatchThresholds.defaults,
      now: DateTime.utc(2026, 9, 27, 12),
      probe: (_) async => throw StateError('ssh down'),
    );
    final cached = (await repo.loadFleetCacheByHost())[host.id]!;
    expect(cached.reachable, isFalse);
    expect(cached.pendingUpdates, 7);
    expect(cached.securityUpdates, 2);
  });
}
