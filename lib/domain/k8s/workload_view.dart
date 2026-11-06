import 'package:kelola/domain/k8s/workload.dart';

/// Line under the Kubernetes home workload pills when nothing needs listing.
/// Zero rows from a cluster we could not read says nothing about readiness.
String workloadsAllClearLine({required bool apiReachable, required int rows}) {
  if (!apiReachable) {
    return 'Could not read workloads';
  }
  return rows == 0 ? 'No workloads listed' : 'All listed workloads ready';
}

class WorkloadListView {
  const WorkloadListView({required this.rows});

  final List<K8sWorkload> rows;

  factory WorkloadListView.build(
    List<K8sWorkload> inventory, {
    String namespace = '',
    K8sKind? kind,
    bool notReadyOnly = false,
    String query = '',
  }) {
    final q = query.trim().toLowerCase();
    return WorkloadListView(
      rows: [
        for (final row in inventory)
          if ((namespace.isEmpty || row.namespace == namespace) &&
              (kind == null || row.kind == kind) &&
              (!notReadyOnly || row.notReady) &&
              (q.isEmpty ||
                  row.name.toLowerCase().contains(q) ||
                  row.namespace.toLowerCase().contains(q)))
            row,
      ],
    );
  }
}

/// `pod · 0/1 · CrashLoopBackOff · 14 restarts`
String workloadMeta(K8sWorkload row) {
  final parts = <String>[
    row.kind.short,
    row.readyLabel,
    if (row.phase.isNotEmpty) row.phase,
    if (row.restarts > 0)
      '${row.restarts} restart${row.restarts == 1 ? '' : 's'}',
  ];
  return parts.join(' · ');
}

List<String> workloadNamespaces(List<K8sWorkload> rows) {
  final set = {for (final row in rows) row.namespace};
  final list = set.where((n) => n.isNotEmpty).toList()..sort();
  return list;
}

const workloadEmptyCopy =
    'No kubectl on this host. Kelola reaches the cluster through this machine, not a kubeconfig on the phone.';

const workloadNoneCopy = 'No workloads in this filter.';
