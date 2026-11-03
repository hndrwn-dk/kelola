import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';

/// Wave 2 read models: cluster-wide events, Services + Endpoints, PV/PVC.
/// Parsed from `kubectl get … -A -o json` (see cluster_resources_parser).

class K8sClusterEvent {
  const K8sClusterEvent({
    required this.namespace,
    required this.type,
    required this.reason,
    required this.message,
    required this.objectKind,
    required this.objectName,
    this.count = 1,
    this.at,
  });

  final String namespace;

  /// `Warning` or `Normal`.
  final String type;
  final String reason;
  final String message;

  /// involvedObject.kind, e.g. `Pod`, `Deployment`, `Node`.
  final String objectKind;
  final String objectName;
  final int count;
  final DateTime? at;

  bool get warning => type == 'Warning';

  String get objectLabel {
    final ns = namespace.isEmpty ? '' : '$namespace/';
    return '$objectKind $ns$objectName';
  }
}

class K8sServicePort {
  const K8sServicePort({
    required this.port,
    this.nodePort,
    this.protocol = 'TCP',
    this.targetPort = '',
  });

  final int port;
  final int? nodePort;
  final String protocol;

  /// Number or named container port; empty when the spec omits it.
  final String targetPort;

  /// `80:30080/TCP → http`. The arrow is dropped when target == port.
  String get label {
    final base = '$port${nodePort == null ? '' : ':$nodePort'}/$protocol';
    if (targetPort.isEmpty || targetPort == '$port') {
      return base;
    }
    return '$base → $targetPort';
  }
}

/// One Endpoints address. [targetName] is empty for manual Endpoints.
class K8sEndpointAddress {
  const K8sEndpointAddress({
    required this.ip,
    required this.ready,
    this.nodeName = '',
    this.targetKind = '',
    this.targetNamespace = '',
    this.targetName = '',
  });

  final String ip;
  final bool ready;
  final String nodeName;
  final String targetKind;
  final String targetNamespace;
  final String targetName;
}

class K8sService {
  const K8sService({
    required this.namespace,
    required this.name,
    required this.type,
    required this.clusterIp,
    required this.ports,
    required this.hasSelector,
    this.readyEndpoints = 0,
    this.notReadyEndpoints = 0,
    this.externalAddress = '',
    this.selector = const {},
    this.portList = const [],
    this.addresses = const [],
  });

  /// `spec.selector`, for the detail screen.
  final Map<String, String> selector;
  final List<K8sServicePort> portList;

  /// One row per IP, ready rows first. Counts above agree with this.
  final List<K8sEndpointAddress> addresses;

  String get selectorLabel =>
      [for (final e in selector.entries) '${e.key}=${e.value}'].join(', ');

  final String namespace;
  final String name;

  /// ClusterIP / NodePort / LoadBalancer / ExternalName.
  final String type;
  final String clusterIp;

  /// `80/TCP, 443/TCP` (NodePort shown as `80:30080/TCP`).
  final String ports;

  /// Services without a selector (manual Endpoints, ExternalName) are not
  /// judged on endpoint count.
  final bool hasSelector;
  final int readyEndpoints;
  final int notReadyEndpoints;

  /// LoadBalancer ingress IP/hostname, or ExternalName target.
  final String externalAddress;

  String get title => '$namespace/$name';

  bool get noEndpoints => hasSelector && readyEndpoints == 0;

  bool get loadBalancerPending =>
      type == 'LoadBalancer' && externalAddress.isEmpty;

  HealthStatus get health {
    if (noEndpoints) {
      return HealthStatus.failed;
    }
    if (loadBalancerPending || notReadyEndpoints > 0) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }

  String get endpointsLabel {
    if (!hasSelector) {
      return type == 'ExternalName' ? 'external' : 'no selector';
    }
    final total = readyEndpoints + notReadyEndpoints;
    return '$readyEndpoints/$total endpoints';
  }
}

class K8sVolumeClaim {
  const K8sVolumeClaim({
    required this.namespace,
    required this.name,
    required this.phase,
    this.capacity = '',
    this.requested = '',
    this.storageClass = '',
    this.volumeName = '',
    this.accessModes = const [],
  });

  final List<String> accessModes;

  String get accessModesLabel => k8sAccessModesLabel(accessModes);

  final String namespace;
  final String name;

  /// Bound / Pending / Lost.
  final String phase;
  final String capacity;
  final String requested;
  final String storageClass;
  final String volumeName;

  String get title => '$namespace/$name';

  HealthStatus get health => switch (phase) {
        'Bound' => HealthStatus.healthy,
        'Pending' => HealthStatus.warning,
        'Lost' => HealthStatus.failed,
        _ => HealthStatus.unknown,
      };
}

class K8sPersistentVolume {
  const K8sPersistentVolume({
    required this.name,
    required this.phase,
    this.capacity = '',
    this.claim = '',
    this.reclaimPolicy = '',
    this.storageClass = '',
    this.accessModes = const [],
  });

  final List<String> accessModes;

  String get accessModesLabel => k8sAccessModesLabel(accessModes);

  final String name;

  /// Available / Bound / Released / Failed / Pending.
  final String phase;
  final String capacity;

  /// `namespace/name` of the bound claim, or empty.
  final String claim;
  final String reclaimPolicy;
  final String storageClass;

  HealthStatus get health => switch (phase) {
        'Bound' || 'Available' => HealthStatus.healthy,
        'Released' || 'Pending' => HealthStatus.warning,
        'Failed' => HealthStatus.failed,
        _ => HealthStatus.unknown,
      };
}

class K8sNetworking {
  const K8sNetworking({required this.services});

  final List<K8sService> services;

  int get noEndpointCount => services.where((s) => s.noEndpoints).length;

  int get lbPendingCount =>
      services.where((s) => s.loadBalancerPending).length;
}

class K8sStorage {
  const K8sStorage({required this.claims, required this.volumes});

  final List<K8sVolumeClaim> claims;
  final List<K8sPersistentVolume> volumes;

  int get pendingClaims => claims.where((c) => c.phase == 'Pending').length;

  int get lostClaims => claims.where((c) => c.phase == 'Lost').length;

  int get unhealthyVolumes =>
      volumes.where((v) => v.health != HealthStatus.healthy).length;
}

/// One container image in a revision's pod template.
class K8sRevisionImage {
  const K8sRevisionImage({
    required this.name,
    required this.image,
    this.init = false,
  });

  final String name;
  final String image;
  final bool init;

  String get label => init ? '$name (init)' : name;
}

/// Wave 4: one kept revision of a Deployment (ReplicaSet) or a
/// StatefulSet / DaemonSet (ControllerRevision).
class K8sRevision {
  const K8sRevision({
    required this.ownerKind,
    required this.namespace,
    required this.ownerName,
    required this.revision,
    this.createdAt,
    this.images = const [],
    this.restartedAt = '',
    this.changeCause = '',
    this.rollback = false,
    this.changes = const [],
    this.current = false,
    DateTime? changedAt,
    this.changedAfter = false,
  }) : _changedAt = changedAt;

  final K8sKind ownerKind;
  final String namespace;
  final String ownerName;
  final int revision;

  /// ReplicaSet / ControllerRevision creationTimestamp. For a [rollback]
  /// this is when the template first ran, not when it was rolled back to.
  final DateTime? createdAt;
  final List<K8sRevisionImage> images;

  /// Pod template annotation `kubectl.kubernetes.io/restartedAt`.
  final String restartedAt;

  /// Annotation `kubernetes.io/change-cause`.
  final String changeCause;

  /// A ReplicaSet reused by `rollout undo` (it carries
  /// `deployment.kubernetes.io/revision-history`).
  final bool rollback;

  /// What differs from the previous kept revision of the same owner.
  final List<String> changes;

  /// Highest kept revision of its owner.
  final bool current;

  /// When the change happened, as far as the cluster records it. Equal to
  /// [createdAt], except for a reused template ([changedAfter]): then it is
  /// the creation time of the newest lower revision, and the change
  /// happened at some point after it.
  DateTime? get changedAt => _changedAt ?? createdAt;
  final DateTime? _changedAt;
  final bool changedAfter;

  /// `12m`, or `<12m` when only a lower bound on the time is known.
  String ageLabel(DateTime now) {
    final age = k8sAge(changedAt, now);
    if (age.isEmpty) {
      return '';
    }
    return changedAfter ? '<$age' : age;
  }

  String get ownerTitle => '$namespace/$ownerName';

  String get ownerLabel => '${ownerKind.short} $ownerTitle';

  String get changeLabel => changes.join(' · ');

  bool ownedBy(K8sWorkload w) =>
      w.kind == ownerKind && w.namespace == namespace && w.name == ownerName;
}

/// Kept revisions of [w], newest revision first.
List<K8sRevision> revisionsOf(List<K8sRevision> all, K8sWorkload w) {
  return [
    for (final r in all)
      if (r.ownedBy(w)) r,
  ]..sort((a, b) => b.revision.compareTo(a.revision));
}

/// Deployments, StatefulSets and DaemonSets keep rollout history.
bool workloadHasHistory(K8sKind kind) =>
    kind == K8sKind.deployment ||
    kind == K8sKind.statefulSet ||
    kind == K8sKind.daemonSet;

/// `ReadWriteOnce` → `RWO`, the short forms kubectl prints.
String k8sAccessModesLabel(List<String> modes) {
  return [
    for (final m in modes)
      switch (m) {
        'ReadWriteOnce' => 'RWO',
        'ReadOnlyMany' => 'ROX',
        'ReadWriteMany' => 'RWX',
        'ReadWriteOncePod' => 'RWOP',
        _ => m,
      },
  ].join(', ');
}

/// Short age like `45s`, `12m`, `3h`, `2d`. Empty when unknown.
String k8sAge(DateTime? at, DateTime now) {
  if (at == null) {
    return '';
  }
  final d = now.difference(at);
  if (d.isNegative || d.inSeconds < 60) {
    return '${d.isNegative ? 0 : d.inSeconds}s';
  }
  if (d.inMinutes < 60) {
    return '${d.inMinutes}m';
  }
  if (d.inHours < 48) {
    return '${d.inHours}h';
  }
  return '${d.inDays}d';
}

/// Healthy rows last, then by title. Used for the "worst N" home lists.
int worstHealthFirst(HealthStatus a, HealthStatus b) {
  int rank(HealthStatus h) => switch (h) {
        HealthStatus.failed => 0,
        HealthStatus.warning => 1,
        HealthStatus.unknown => 2,
        HealthStatus.healthy => 3,
      };
  return rank(a).compareTo(rank(b));
}

/// kubectl produced no JSON (RBAC denied, API down, resource unsupported).
/// Thrown by Wave 2 probes so "none found" and "could not read" differ.
class K8sReadException implements Exception {
  K8sReadException(this.what, this.detail);

  final String what;
  final String detail;

  @override
  String toString() =>
      detail.isEmpty ? 'Could not read $what' : 'Could not read $what: $detail';
}
