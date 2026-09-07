import 'package:kelola/domain/fleet/fleet_health.dart';

List<FleetIssue> fleetIssues(FleetHostHealth health) =>
    assessFleetHost(health).issues;

/// Context actions: at most two actionable issues, highest priority first.
List<FleetIssue> fleetQuickActions(FleetHostHealth health) {
  return fleetIssues(health)
      .where((i) => i.isActionable)
      .take(2)
      .toList(growable: false);
}

String? fleetMoreIssuesLabel(FleetHostHealth health) {
  final actionable = fleetIssues(health).where((i) => i.isActionable).length;
  if (actionable <= 2) {
    return null;
  }
  return '+${actionable - 2} more issues';
}
