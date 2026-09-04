import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

void main() {
  test('sorts by severity then alias', () {
    final rows = [
      FleetHostHealth(
        hostId: 'a',
        alias: 'alpha',
        reachable: true,
        load1: 0.1,
        diskRootPercent: 10,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'b',
        alias: 'bravo',
        reachable: false,
        load1: 0,
        diskRootPercent: 0,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'c',
        alias: 'charlie',
        reachable: true,
        load1: 0.2,
        diskRootPercent: 95,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'd',
        alias: 'delta',
        reachable: true,
        load1: 0.2,
        diskRootPercent: 20,
        failedUnitCount: 3,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'e',
        alias: 'echo',
        reachable: true,
        load1: 5.0,
        diskRootPercent: 20,
        failedUnitCount: 0,
        pendingUpdates: 2,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'f',
        alias: 'foxtrot',
        reachable: true,
        load1: 0.1,
        diskRootPercent: 20,
        failedUnitCount: 0,
        pendingUpdates: 4,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
      FleetHostHealth(
        hostId: 'g',
        alias: 'golf',
        reachable: true,
        load1: 5.0,
        diskRootPercent: 20,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 1, 1),
      ),
    ];

    final sorted = sortFleetHealth(rows).map((h) => h.alias).toList();
    expect(sorted, [
      'bravo',
      'delta',
      'charlie',
      'echo',
      'foxtrot',
      'golf',
      'alpha',
    ]);
  });
}
