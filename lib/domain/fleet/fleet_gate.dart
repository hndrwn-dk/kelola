import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class FleetReadOnlyViolation implements Exception {
  FleetReadOnlyViolation(this.probe);

  final Probe<dynamic> probe;

  @override
  String toString() =>
      'Fleet mode refuses ${probe.runtimeType} (${probe.risk.name})';
}

/// Fleet may only run [RiskLevel.read] probes. Mutate/destructive throw.
void assertFleetReadOnly(Probe<dynamic> probe, {required ProbeScope scope}) {
  if (scope != ProbeScope.fleet) {
    return;
  }
  if (probe.risk != RiskLevel.read) {
    throw FleetReadOnlyViolation(probe);
  }
}
