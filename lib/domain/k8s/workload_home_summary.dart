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
  });

  final int deployments;
  final int statefulSets;
  final int daemonSets;
  final int pods;
  final int notReadyCount;
  final List<K8sWorkload> worst;

  factory WorkloadHomeSummary.from(
    List<K8sWorkload> rows, {
    int worstLimit = 3,
  }) {
    var deployments = 0;
    var statefulSets = 0;
    var daemonSets = 0;
    var pods = 0;
    final notReady = <K8sWorkload>[];
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
      if (row.notReady) {
        notReady.add(row);
      }
    }
    notReady.sort(_worstFirst);
    return WorkloadHomeSummary(
      deployments: deployments,
      statefulSets: statefulSets,
      daemonSets: daemonSets,
      pods: pods,
      notReadyCount: notReady.length,
      worst: notReady.take(worstLimit).toList(growable: false),
    );
  }
}

int _worstFirst(K8sWorkload a, K8sWorkload b) {
  final rank = _healthRank(a.health).compareTo(_healthRank(b.health));
  if (rank != 0) {
    return rank;
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

/// null when no CoreDNS-shaped pod is in the inventory.
bool? coreDnsReadyFromWorkloads(List<K8sWorkload> rows) {
  final dns = [
    for (final row in rows)
      if (row.kind == K8sKind.pod &&
          row.namespace == 'kube-system' &&
          row.name.toLowerCase().contains('coredns'))
        row,
  ];
  if (dns.isEmpty) {
    return null;
  }
  return dns.every((p) => !p.notReady && p.health == HealthStatus.healthy);
}
