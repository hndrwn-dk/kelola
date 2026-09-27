import 'package:kelola/domain/k8s/workload.dart';

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

List<String> workloadNamespaces(List<K8sWorkload> rows) {
  final set = {for (final row in rows) row.namespace};
  final list = set.where((n) => n.isNotEmpty).toList()..sort();
  return list;
}

const workloadEmptyCopy =
    'No kubectl on this host. Kelola reaches the cluster through this machine, not a kubeconfig on the phone.';

const workloadNoneCopy = 'No workloads in this filter.';
