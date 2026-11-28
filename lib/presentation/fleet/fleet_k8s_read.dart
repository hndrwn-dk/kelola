import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
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
  void Function(ClusterHealth health)? onClusterKind,
  bool? cachedHasArgo,
}) async {
  if (kubectlFlavor(facts) == KubectlFlavor.none) {
    return null;
  }
  try {
    const clusterProbe = FleetClusterProbe();
    assertFleetReadOnly(clusterProbe, scope: ProbeScope.fleet);
    final cluster = await run(clusterProbe);
    // M48: feed the same cluster-kind cache the Kubernetes home writes,
    // only when the read could tell OpenShift from Kubernetes.
    if (cluster.health.isOpenShift != null) {
      try {
        onClusterKind?.call(cluster.health);
      } catch (_) {
        // Cache only.
      }
    }
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
    var summary = fleetK8sSummary(cluster, inv, previous: previous);
    if (!summary.read) {
      return summary;
    }
    // M48 §5: OpenShift rides the call fleet already made. A failure leaves
    // ocp null and keeps the rest of the summary.
    if (cluster.health.isOpenShift == true) {
      try {
        const ocpProbe = FleetOpenShiftProbe();
        assertFleetReadOnly(ocpProbe, scope: ProbeScope.fleet);
        final ocp = await run(ocpProbe);
        summary = summary.withOcp(
          FleetOcpSummary.from(ocp.withNodes(cluster.health.nodes)),
        );
      } catch (_) {
        // ocp stays null.
      }
    }
    // M49: Argo CD, independent of OpenShift. Fresh detection wins over the
    // cached kind; unknown on both sides never probes.
    if ((cluster.health.hasArgo ?? cachedHasArgo) == true) {
      try {
        const argoProbe = FleetArgoProbe();
        assertFleetReadOnly(argoProbe, scope: ProbeScope.fleet);
        final apps = await run(argoProbe);
        summary = summary.withArgo(FleetArgoSummary.from(apps));
      } catch (_) {
        // argo stays null.
      }
    }
    return summary;
  } catch (_) {
    return FleetK8sSummary.unreadable;
  }
}
