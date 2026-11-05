import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';

/// M48.1: which OpenShift distribution a cluster runs.
enum OpenShiftDistro { ocp, okd }

const _okdImagePrefixes = ['CentOS Stream CoreOS', 'Fedora CoreOS'];
const _ocpImagePrefix = 'Red Hat Enterprise Linux CoreOS';

/// Version wins; osImage only when version is empty. Null = unknown: never
/// claim OKD without evidence.
OpenShiftDistro? openShiftDistroFrom({
  String version = '',
  Iterable<String> osImages = const [],
}) {
  final v = version.trim();
  if (v.isNotEmpty) {
    return v.toLowerCase().contains('okd')
        ? OpenShiftDistro.okd
        : OpenShiftDistro.ocp;
  }
  var okd = false;
  var ocp = false;
  for (final raw in osImages) {
    final image = raw.trim();
    if (_okdImagePrefixes.any(image.startsWith)) {
      okd = true;
    } else if (image.startsWith(_ocpImagePrefix)) {
      ocp = true;
    }
  }
  if (okd == ocp) {
    // Neither, or a mix of both.
    return null;
  }
  return okd ? OpenShiftDistro.okd : OpenShiftDistro.ocp;
}

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
    this.distro,
  });

  final bool isOpenShift;

  /// When [isOpenShift] was read.
  final DateTime readAt;

  /// Context [isOpenShift] was read under. Empty when unknown.
  final String kubeContext;

  /// Context reported by the newest read, when that read could not tell
  /// the kind. Null when no newer read reported a context.
  final String? seenContext;

  /// M48.1: OKD vs OCP, when known. Null = unknown (label stays OpenShift).
  final OpenShiftDistro? distro;

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
      // A fresh hint wins; otherwise the old distro only survives on the
      // same context (an unknown context is not a change).
      distro:
          read.distroHint ??
          (previous != null &&
                  _sameContext(previous.kubeContext, read.kubeContext)
              ? previous.distro
              : null),
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
    distro: previous.distro,
  );
}

bool _sameContext(String a, String b) => a.isEmpty || b.isEmpty || a == b;

/// [record] with [distro] set and nothing else changed. A distro read
/// older than the kind read is ignored, so a slow result cannot undo a
/// newer read.
ClusterKindRecord withDistro(
  ClusterKindRecord record,
  OpenShiftDistro distro,
  DateTime at,
) {
  if (at.toUtc().isBefore(record.readAt.toUtc())) {
    return record;
  }
  return ClusterKindRecord(
    isOpenShift: record.isOpenShift,
    readAt: record.readAt,
    kubeContext: record.kubeContext,
    seenContext: record.seenContext,
    distro: distro,
  );
}
