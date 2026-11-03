import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_actions.dart';

/// M32: namespaces that hold something `rollout restart` accepts
/// (Deployments, StatefulSets, DaemonSets). Add-on `kube-*` namespaces last.
List<String> bulkRestartNamespaces(List<K8sWorkload> rows) {
  final names = <String>{
    for (final w in rows)
      if (workloadCanRestart(w.kind) && w.namespace.isNotEmpty) w.namespace,
  }.toList();
  names.sort((a, b) {
    final ak = a.startsWith('kube-');
    final bk = b.startsWith('kube-');
    if (ak != bk) {
      return ak ? 1 : -1;
    }
    return a.compareTo(b);
  });
  return names;
}

/// Restartable workloads in [namespace], by kind then name.
List<K8sWorkload> bulkRestartCandidates(
  List<K8sWorkload> rows,
  String namespace,
) {
  return [
    for (final w in rows)
      if (workloadCanRestart(w.kind) && w.namespace == namespace) w,
  ]..sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.name.compareTo(b.name);
    });
}

/// Add-ons the operator usually does not own start unchecked.
bool bulkRestartCheckedByDefault(String namespace) =>
    !namespace.startsWith('kube-');
