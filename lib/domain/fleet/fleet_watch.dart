import 'package:kelola/domain/fleet/fleet_health.dart';

const Duration kFleetWatchMinInterval = Duration(hours: 1);

const Set<FleetIssueKind> kFleetWatchKinds = {
  FleetIssueKind.unreachable,
  FleetIssueKind.failedUnit,
  FleetIssueKind.badContainer,
  FleetIssueKind.diskCritical,
  FleetIssueKind.memHigh,
  FleetIssueKind.rebootRequired,
};

FleetAssessment fleetWatchAssessment(
  FleetHostHealth health,
  FleetWatchThresholds thresholds,
) {
  final raw = assessFleetHost(health, thresholds: thresholds);
  final kept = [
    for (final issue in raw.issues)
      if (kFleetWatchKinds.contains(issue.kind)) issue,
  ];
  if (kept.isEmpty) {
    return const FleetAssessment(
      severity: FleetSeverity.healthy,
      tileHealth: FleetTileHealth.healthy,
      issues: [],
    );
  }
  return FleetAssessment(
    severity: raw.severity,
    tileHealth: raw.tileHealth,
    issues: List.unmodifiable(kept),
  );
}

String fleetWatchFingerprint(FleetAssessment assessment) {
  if (assessment.issues.isEmpty) {
    return 'healthy';
  }
  final kinds = assessment.issues.map((i) => i.kind.name).toList()..sort();
  return kinds.join('|');
}

bool fleetWatchShouldNotify({
  required String? previous,
  required String current,
}) {
  if (previous == null) {
    return false;
  }
  return previous != current;
}

bool fleetWatchIsDue({
  required DateTime? lastTickUtc,
  required DateTime now,
}) {
  if (lastTickUtc == null) {
    return true;
  }
  return !now.toUtc().isBefore(lastTickUtc.toUtc().add(kFleetWatchMinInterval));
}

String fleetWatchNoticeBody(FleetAssessment assessment) {
  if (assessment.issues.isEmpty) {
    return 'recovered';
  }
  return assessment.issues.map((i) => i.meta).join(' · ');
}
