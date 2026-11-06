import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';

class WorkloadHomeSummary {
  const WorkloadHomeSummary({
    required this.deployments,
    required this.statefulSets,
    required this.daemonSets,
    required this.pods,
    required this.notReadyCount,
    required this.worst,
    this.pendingCount = 0,
    this.crashLoopCount = 0,
    this.restartingCount = 0,
  });

  final int deployments;
  final int statefulSets;
  final int daemonSets;
  final int pods;
  final int notReadyCount;
  final List<K8sWorkload> worst;

  /// Pods in phase Pending (unscheduled, pulling, creating).
  final int pendingCount;

  /// Pods whose container (or init container) is in CrashLoopBackOff.
  final int crashLoopCount;

  /// Pods with at least [kRestartWarn] restarts.
  final int restartingCount;

  factory WorkloadHomeSummary.from(
    List<K8sWorkload> rows, {
    int worstLimit = 3,
  }) {
    var deployments = 0;
    var statefulSets = 0;
    var daemonSets = 0;
    var pods = 0;
    var pending = 0;
    var crashLoop = 0;
    var restarting = 0;
    final notReady = <K8sWorkload>[];
    final flapping = <K8sWorkload>[];
    for (final row in rows) {
      switch (row.kind) {
        case K8sKind.deployment:
          deployments++;
        case K8sKind.statefulSet:
          statefulSets++;
        case K8sKind.daemonSet:
          daemonSets++;
        case K8sKind.pod:
          pods++;
        case K8sKind.job:
        case K8sKind.cronJob:
          break;
      }
      if (row.pending) {
        pending++;
      }
      if (row.crashLooping) {
        crashLoop++;
      }
      if (row.restarting) {
        restarting++;
      }
      if (row.notReady) {
        notReady.add(row);
      } else if (row.readyButRestarting) {
        flapping.add(row);
      }
    }
    notReady.sort(_worstFirst);
    flapping.sort(_worstFirst);
    return WorkloadHomeSummary(
      deployments: deployments,
      statefulSets: statefulSets,
      daemonSets: daemonSets,
      pods: pods,
      notReadyCount: notReady.length,
      worst: [...notReady, ...flapping].take(worstLimit).toList(growable: false),
      pendingCount: pending,
      crashLoopCount: crashLoop,
      restartingCount: restarting,
    );
  }
}

int _worstFirst(K8sWorkload a, K8sWorkload b) {
  final rank = _healthRank(a.health).compareTo(_healthRank(b.health));
  if (rank != 0) {
    return rank;
  }
  final restarts = b.restarts.compareTo(a.restarts);
  if (restarts != 0) {
    return restarts;
  }
  return a.title.compareTo(b.title);
}

int _healthRank(HealthStatus h) {
  return switch (h) {
    HealthStatus.failed => 0,
    HealthStatus.warning => 1,
    HealthStatus.unknown => 2,
    HealthStatus.healthy => 3,
  };
}

/// null when no CoreDNS-shaped pod is in the inventory. M48: OpenShift runs
/// `dns-default-*` pods in `openshift-dns` instead of CoreDNS in kube-system.
bool? coreDnsReadyFromWorkloads(List<K8sWorkload> rows) {
  final dns = [
    for (final row in rows)
      if (row.kind == K8sKind.pod &&
          ((row.namespace == 'kube-system' &&
                  row.name.toLowerCase().contains('coredns')) ||
              (row.namespace == 'openshift-dns' &&
                  row.name.toLowerCase().startsWith('dns-default'))))
        row,
  ];
  if (dns.isEmpty) {
    return null;
  }
  return dns.every(
    (p) =>
        !p.notReady &&
        (p.health == HealthStatus.healthy || p.readyButRestarting),
  );
}
