import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_actions.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

void main() {
  FleetHostHealth base({
    int failed = 0,
    int containersDown = 0,
    int containersUnhealthy = 0,
    int disk = 10,
    List<String> highDisk = const [],
    int security = 0,
    int pending = 0,
  }) {
    return FleetHostHealth(
      hostId: 'h1',
      alias: 'web',
      reachable: true,
      load1: 0.2,
      nprocCores: 4,
      memPercent: 40,
      diskRootPercent: disk,
      highDiskMounts: highDisk,
      failedUnitCount: failed,
      pendingUpdates: pending,
      securityUpdates: security,
      containersDown: containersDown,
      containersUnhealthy: containersUnhealthy,
      uptime: const Duration(hours: 3),
      rebootRequired: false,
      fetchedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('quick actions take top two by priority', () {
    final h = base(
      failed: 1,
      containersDown: 2,
      disk: 95,
      security: 3,
    );
    final actions = fleetQuickActions(h);
    expect(actions.map((a) => a.kind).toList(), [
      FleetIssueKind.failedUnit,
      FleetIssueKind.badContainer,
    ]);
    expect(fleetMoreIssuesLabel(h), '+2 more issues');
  });

  test('disk-only host does not offer restart unit', () {
    final h = base(disk: 96, highDisk: const ['/var:91%']);
    final actions = fleetQuickActions(h);
    expect(actions, hasLength(1));
    expect(actions.single.kind, FleetIssueKind.diskCritical);
    expect(fleetMoreIssuesLabel(h), isNull);
  });

  test('exit 0 containers are not trouble', () {
    expect(
      countFleetContainerTrouble([
        'exited\tExited (0) 2 days ago\tbatch',
        'running\tUp 1 day (healthy)\tweb',
      ]),
      (down: 0, unhealthy: 0),
    );
    expect(
      countFleetContainerTrouble([
        'exited\tExited (1) 2 hours ago\tjob',
        'restarting\tRestarting (1) 5 seconds ago\tapi',
        'running\tUp 1 day (unhealthy)\tdb',
      ]),
      (down: 2, unhealthy: 1),
    );
  });
}
