import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';

void main() {
  test('tileMetrics always has load mem disk up; omits zero trouble fields', () {
    final h = FleetHostHealth(
      hostId: 'a',
      alias: 'east',
      reachable: true,
      load1: 1.14,
      nprocCores: 1,
      memPercent: 42,
      diskRootPercent: 67,
      failedUnitCount: 0,
      pendingUpdates: 0,
      securityUpdates: 0,
      containersDown: 0,
      containersUnhealthy: 0,
      uptime: const Duration(minutes: 3),
      fetchedAt: DateTime.utc(2026, 1, 1),
    );
    final now = DateTime.utc(2026, 1, 1, 0, 5);
    final labels = h.tileMetrics(now: now).map((m) => m.label).toList();
    expect(labels, ['load', 'mem', 'disk', 'up']);
    expect(h.tileMetrics(now: now).singleWhere((m) => m.label == 'up').value, '3m');
    expect(
      h.tileMetrics(now: now).singleWhere((m) => m.label == 'load').value,
      '114%',
    );
  });

  test('tileMetrics includes failed containers updates only when non-zero', () {
    final h = FleetHostHealth(
      hostId: 'b',
      alias: 'west',
      reachable: true,
      load1: 0.2,
      nprocCores: 4,
      memPercent: 10,
      diskRootPercent: 20,
      failedUnitCount: 2,
      pendingUpdates: 3,
      securityUpdates: 1,
      containersDown: 1,
      containersUnhealthy: 0,
      uptime: const Duration(hours: 5),
      rebootRequired: true,
      fetchedAt: DateTime.utc(2026, 1, 1),
    );
    final labels = h.tileMetrics().map((m) => m.label).toList();
    expect(labels, containsAll(['fail', 'ctr', 'sec', 'reboot', 'up']));
    expect(labels, isNot(contains('upd')));
  });

  test('load over 100% uses failed health (red band), not warning amber', () {
    final h = FleetHostHealth(
      hostId: 'c',
      alias: 'east-controlpanel-uat',
      reachable: true,
      load1: 1.14,
      nprocCores: 1,
      memPercent: 40,
      diskRootPercent: 50,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.utc(2026, 1, 1),
    );
    expect(h.severity, FleetSeverity.loadHigh);
    expect(h.tileRiskLevel, RiskLevel.destructive);
    expect(fleetTileHealthStatus(h), HealthStatus.failed);
  });
}
