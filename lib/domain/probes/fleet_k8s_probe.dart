import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// What the fleet cluster read saw. [nodesRead] is false when kubectl
/// printed no node JSON; [connectionRefused] says why when stderr shows the
/// API itself did not answer (as opposed to RBAC or sudo).
typedef FleetClusterRead = ({
  ClusterHealth health,
  bool nodesRead,
  bool connectionRefused,
});

/// M32: the Kubernetes home cluster read, run from fleet. Same command as
/// [ClusterHealthProbe]; parse also looks at stderr so "API down" and
/// "not allowed to ask" do not look the same.
class FleetClusterProbe extends Probe<FleetClusterRead> {
  const FleetClusterProbe();

  static final _refused = RegExp(
    r'Unable to connect to the server|connection refused|'
    r'dial tcp|i/o timeout|no route to host|TLS handshake timeout',
    caseSensitive: false,
  );

  /// kubectl with no kubeconfig falls back to `localhost:8080` and reports
  /// it refused. That is "no access" (often root without a kubeconfig on the
  /// sudo fallback), not a dead API, so it must not page.
  static bool _apiDidNotAnswer(String stderr) {
    if (stderr.contains('localhost:8080')) {
      return false;
    }
    return _refused.hasMatch(stderr);
  }

  @override
  String get auditTitle => 'Read cluster health (fleet)';

  @override
  String command(HostFacts facts) => const ClusterHealthProbe().command(facts);

  @override
  FleetClusterRead parse(String stdout, String stderr, int exitCode) {
    final marker = stdout.indexOf('---NODES---');
    final nodes = marker < 0 ? '' : stdout.substring(marker);
    return (
      health: parseClusterHealth(stdout),
      nodesRead: nodes.contains('{'),
      connectionRefused: _apiDidNotAnswer(stderr),
    );
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

/// The workload list, run from fleet. Same command as [WorkloadListProbe],
/// but kubectl output with no JSON throws instead of reading as an empty
/// cluster, so the summary keeps the last known counts (never "recovered").
class FleetWorkloadListProbe extends WorkloadListProbe {
  const FleetWorkloadListProbe();

  @override
  String get auditTitle => 'Listed workloads (fleet)';

  @override
  WorkloadInventory parse(String stdout, String stderr, int exitCode) {
    if (!stdout.contains('{') && !stdout.contains('---NO_KUBECTL---')) {
      throw K8sReadException('workloads', stderr.trim().split('\n').first);
    }
    return super.parse(stdout, stderr, exitCode);
  }
}

/// Fold the two fleet reads into a summary. Unreadable (RBAC, k3s without
/// passwordless sudo) never pages; a refused connection is "API down".
///
/// [inv] null means the workload list failed: workload counts are carried
/// from [previous] so a timeout does not read as "recovered".
FleetK8sSummary fleetK8sSummary(
  FleetClusterRead read,
  WorkloadInventory? inv, {
  FleetK8sSummary? previous,
}) {
  if (read.health.missingKubectl) {
    return FleetK8sSummary.unreadable;
  }
  if (!read.nodesRead) {
    return read.connectionRefused
        ? FleetK8sSummary.apiDown
        : FleetK8sSummary.unreadable;
  }
  if (inv == null) {
    final base =
        FleetK8sSummary.from(read.health, const WorkloadInventory(rows: []));
    final carried = previous != null && previous.read ? previous : null;
    return FleetK8sSummary(
      read: true,
      apiReachable: base.apiReachable,
      nodesReady: base.nodesReady,
      nodesTotal: base.nodesTotal,
      failedWorkloads: carried?.failedWorkloads ?? 0,
      warningWorkloads: carried?.warningWorkloads ?? 0,
    );
  }
  return FleetK8sSummary.from(read.health, inv);
}
