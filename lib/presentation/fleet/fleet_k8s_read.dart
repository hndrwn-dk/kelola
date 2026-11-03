import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';

/// Runs one probe for a host. The fleet screen passes `runHostProbe`, fleet
/// watch passes `pool.execute`; both use [ProbeScope.fleet].
typedef FleetProbeRunner = Future<T> Function<T>(Probe<T> probe);

/// M32: the host's cluster as fleet sees it. Null when the host has no
/// kubectl. Any failure is "not readable", never an unreachable host.
/// [previous] (the cached summary) keeps workload counts when only the
/// workload list fails.
Future<FleetK8sSummary?> readFleetK8s(
  HostFacts facts,
  FleetProbeRunner run, {
  FleetK8sSummary? previous,
}) async {
  if (kubectlFlavor(facts) == KubectlFlavor.none) {
    return null;
  }
  try {
    const clusterProbe = FleetClusterProbe();
    assertFleetReadOnly(clusterProbe, scope: ProbeScope.fleet);
    final cluster = await run(clusterProbe);
    WorkloadInventory? inv;
    if (cluster.nodesRead) {
      const listProbe = FleetWorkloadListProbe();
      assertFleetReadOnly(listProbe, scope: ProbeScope.fleet);
      try {
        inv = await run(listProbe);
      } catch (_) {
        // Nodes answered; keep the last known workload counts.
        inv = null;
      }
    }
    return fleetK8sSummary(cluster, inv, previous: previous);
  } catch (_) {
    return FleetK8sSummary.unreadable;
  }
}
