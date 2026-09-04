import 'package:kelola/domain/fleet/fleet_health.dart';

enum FleetIssueKind {
  failedUnit,
  badContainer,
  diskCritical,
  securityUpdates,
}

class FleetIssue {
  const FleetIssue({
    required this.kind,
    required this.label,
    required this.meta,
  });

  final FleetIssueKind kind;
  final String label;
  final String meta;
}

List<FleetIssue> fleetIssues(FleetHostHealth health) {
  final out = <FleetIssue>[];
  if (health.failedUnitCount > 0) {
    out.add(
      FleetIssue(
        kind: FleetIssueKind.failedUnit,
        label: 'Restart failed unit',
        meta: '${health.failedUnitCount} failed',
      ),
    );
  }
  if (health.containerTroubleCount > 0) {
    out.add(
      FleetIssue(
        kind: FleetIssueKind.badContainer,
        label: 'Inspect containers',
        meta: health.containersLabel,
      ),
    );
  }
  if (health.diskRootPercent >= FleetHostHealth.diskHighThreshold ||
      health.highDiskMounts.isNotEmpty) {
    final mounts = [
      if (health.diskRootPercent >= FleetHostHealth.diskHighThreshold)
        '/:${health.diskRootPercent}%',
      ...health.highDiskMounts,
    ].join(' · ');
    out.add(
      FleetIssue(
        kind: FleetIssueKind.diskCritical,
        label: 'Review disk',
        meta: mounts,
      ),
    );
  }
  if (health.securityUpdates > 0) {
    out.add(
      FleetIssue(
        kind: FleetIssueKind.securityUpdates,
        label: 'Security updates',
        meta: '${health.securityUpdates} security',
      ),
    );
  }
  return out;
}

/// Context actions: at most two, highest priority first.
List<FleetIssue> fleetQuickActions(FleetHostHealth health) {
  return fleetIssues(health).take(2).toList(growable: false);
}

String? fleetMoreIssuesLabel(FleetHostHealth health) {
  final n = fleetIssues(health).length;
  if (n <= 2) {
    return null;
  }
  return '+${n - 2} more issues';
}
