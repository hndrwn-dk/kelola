import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_actions.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';

void main() {
  FleetHostHealth base({
    int failed = 1,
    int security = 184,
    int pending = 184,
  }) {
    return FleetHostHealth(
      hostId: 'h1',
      alias: 'east-worker-uat',
      reachable: true,
      load1: 0.2,
      nprocCores: 4,
      memPercent: 40,
      diskRootPercent: 40,
      failedUnitCount: failed,
      pendingUpdates: pending,
      securityUpdates: security,
      uptime: const Duration(hours: 3),
      rebootRequired: false,
      fetchedAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('fleet sheet issues are a single list; actionable kinds stay actionable',
      () {
    final h = base();
    final issues = fleetIssues(h);
    final actions = fleetQuickActions(h);
    // Quick-actions helper still exists for callers that need buttons only,
    // but sheet must not render both identical copies.
    expect(issues.length, greaterThan(actions.length));
    expect(issues.any((i) => i.isActionable), isTrue);
    expect(issues.any((i) => !i.isActionable), isTrue);
    // Pending remains visible even when not actionable.
    expect(
      issues.any((i) => i.kind == FleetIssueKind.pendingUpdates),
      isTrue,
    );
  });
}
