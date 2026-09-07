import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

void main() {
  FleetHostHealth prior({
    double load1 = 0.54,
    int? nprocCores = 1,
    int mem = 20,
  }) {
    return FleetHostHealth(
      hostId: 'h1',
      alias: 'east-rock-uat',
      reachable: true,
      load1: load1,
      nprocCores: nprocCores,
      memPercent: mem,
      diskRootPercent: 13,
      failedUnitCount: 0,
      pendingUpdates: 0,
      uptime: const Duration(hours: 2),
      fetchedAt: DateTime.utc(2026, 9, 7, 2, 0),
    );
  }

  test('surface: tile and sheet load/mem are byte-identical for one sample',
      () {
    final health = applyFleetMetricsSample(
      prior(load1: 0.54, nprocCores: 1, mem: 20),
      load1: 0.39,
      memPercent: 19,
      now: DateTime.utc(2026, 9, 7, 2, 1),
    );

    final tile = health.tileMetrics(now: DateTime.utc(2026, 9, 7, 2, 1));
    final tileLoad = tile.singleWhere((m) => m.label == 'load').value;
    final tileMem = tile.singleWhere((m) => m.label == 'mem').value;

    final live = fleetLiveStrings(health, now: DateTime.utc(2026, 9, 7, 2, 1));

    expect(live.load, tileLoad);
    expect(live.mem, tileMem);
    // Must be %, not the raw MetricsSnapshot loadavg string.
    expect(live.load, '39%');
    expect(live.load, isNot('0.39'));
    expect(live.mem, '19%');
    expect(live.age, isNotEmpty);
  });

  test('surface: without cores both surfaces stay on raw loadavg', () {
    final health = applyFleetMetricsSample(
      prior(load1: 0.54, nprocCores: null, mem: 20),
      load1: 0.39,
      memPercent: 19,
      now: DateTime.utc(2026, 9, 7, 2, 1),
    );
    final live = fleetLiveStrings(health);
    final tileLoad =
        health.tileMetrics().singleWhere((m) => m.label == 'load').value;
    expect(live.load, tileLoad);
    expect(live.load, '0.39');
  });
}
