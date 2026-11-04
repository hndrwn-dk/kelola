import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';

/// M48: one place decides "OpenShift" vs "Kubernetes", so the host
/// dashboard tile and the Kubernetes home band title cannot disagree.
/// Unknown (null) is Kubernetes: never guess OpenShift.
String clusterKindLabel(bool? isOpenShift) =>
    isOpenShift == true ? 'OpenShift' : 'Kubernetes';

/// Last known cluster kind for a host, keyed by the kubeconfig context it
/// was read under, cached so the dashboard can label its Kubernetes tile
/// without SSH.
class ClusterKindRecord {
  const ClusterKindRecord({
    required this.isOpenShift,
    required this.readAt,
    this.kubeContext = '',
    this.seenContext,
  });

  final bool isOpenShift;

  /// When [isOpenShift] was read.
  final DateTime readAt;

  /// Context [isOpenShift] was read under. Empty when unknown.
  final String kubeContext;

  /// Context reported by the newest read, when that read could not tell
  /// the kind. Null when no newer read reported a context.
  final String? seenContext;

  /// False when a newer read reported a different context: the cached kind
  /// belongs to another cluster. An unknown context on either side is not
  /// evidence of a change.
  bool get contextMatches {
    final seen = seenContext;
    if (seen == null || seen.isEmpty || kubeContext.isEmpty) {
      return true;
    }
    return seen == kubeContext;
  }

  /// Tile label. A changed context reads Kubernetes until the next read.
  String get label => clusterKindLabel(contextMatches && isOpenShift);

  /// The 15-minute rule ([Host.attentionFreshFor]).
  bool isStale(DateTime now) =>
      now.toUtc().difference(readAt.toUtc()) > Host.attentionFreshFor;

  /// Tile meta: `cluster` while fresh and current, `cluster · 2h` once
  /// stale or after the context changed. Staleness alone never flips the
  /// label.
  String toolMeta(DateTime now) {
    if (contextMatches && !isStale(now)) {
      return 'cluster';
    }
    final age = k8sAge(readAt.toUtc(), now.toUtc());
    return age.isEmpty ? 'cluster' : 'cluster · $age';
  }
}

/// Fold a new cluster read into the cached record.
///
/// - A known kind (from an API that answered) replaces the record.
/// - An unknown kind keeps the cached kind but notes the context the host
///   now reports, so a switched context is not shown with the old kind.
/// - Returns null when there is nothing to store.
ClusterKindRecord? mergeClusterKind(
  ClusterKindRecord? previous,
  ClusterHealth read,
  DateTime at,
) {
  final kind = read.isOpenShift;
  // Unreachable API: the OpenShift section prints NONE, which is not
  // evidence. (Expired logins already parse as null.)
  if (kind != null && read.apiReachable) {
    return ClusterKindRecord(
      isOpenShift: kind,
      readAt: at.toUtc(),
      kubeContext: read.kubeContext,
    );
  }
  if (previous == null || read.kubeContext.isEmpty) {
    return previous;
  }
  return ClusterKindRecord(
    isOpenShift: previous.isOpenShift,
    readAt: previous.readAt,
    kubeContext: previous.kubeContext,
    seenContext: read.kubeContext,
  );
}
