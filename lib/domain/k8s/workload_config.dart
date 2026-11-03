/// Wave 3: what a workload's pod template asks for. Parsed from the JSON
/// [WorkloadListProbe] already fetches (no extra kubectl call). Never holds
/// env values or Secret data: only names and shapes.
class K8sContainerConfig {
  const K8sContainerConfig({
    required this.name,
    this.image = '',
    this.cpuRequest = '',
    this.memoryRequest = '',
    this.cpuLimit = '',
    this.memoryLimit = '',
    this.readinessProbe = false,
    this.livenessProbe = false,
    this.privileged = false,
    this.init = false,
  });

  final String name;
  final String image;
  final String cpuRequest;
  final String memoryRequest;
  final String cpuLimit;
  final String memoryLimit;
  final bool readinessProbe;
  final bool livenessProbe;
  final bool privileged;

  /// Init containers run to completion; probes do not apply to them.
  final bool init;

  bool get hasRequests => cpuRequest.isNotEmpty || memoryRequest.isNotEmpty;

  /// Memory limit is the one that matters for OOM blast radius.
  bool get hasMemoryLimit => memoryLimit.isNotEmpty;

  String get resourcesLabel {
    String pair(String req, String lim) {
      if (req.isEmpty && lim.isEmpty) {
        return '-';
      }
      return '${req.isEmpty ? '-' : req}/${lim.isEmpty ? '-' : lim}';
    }

    return 'cpu ${pair(cpuRequest, cpuLimit)} · mem ${pair(memoryRequest, memoryLimit)}';
  }
}

/// A ConfigMap or Secret the pod needs. [optional] refs never fail a pod.
class K8sConfigRef {
  const K8sConfigRef({
    required this.kind,
    required this.name,
    this.optional = false,
  });

  /// `ConfigMap` or `Secret`.
  final String kind;
  final String name;
  final bool optional;

  String get key => '$kind/$name/$optional';
}

/// Collects refs once each (a Secret used by env and a volume is one ref).
class _RefSet {
  final _seen = <String>{};
  final refs = <K8sConfigRef>[];

  void add(K8sConfigRef ref) {
    if (_seen.add(ref.key)) {
      refs.add(ref);
    }
  }
}

class K8sPodConfig {
  const K8sPodConfig({
    this.containers = const [],
    this.refs = const [],
    this.serviceAccount = '',
    this.hostNetwork = false,
    this.hostPid = false,
    this.hostIpc = false,
    this.ownedByController = false,
    this.claims = const [],
  });

  final List<K8sContainerConfig> containers;
  final List<K8sConfigRef> refs;

  /// PVC names from `volumes[].persistentVolumeClaim.claimName`. Only real
  /// on Pods: a StatefulSet template names none (volumeClaimTemplates).
  final List<String> claims;
  final String serviceAccount;
  final bool hostNetwork;
  final bool hostPid;
  final bool hostIpc;

  /// Pods created by a Deployment/Job/etc. Their template is judged on the
  /// owner, so owned pods are skipped to avoid double findings.
  final bool ownedByController;

  Iterable<K8sContainerConfig> get appContainers =>
      containers.where((c) => !c.init);

  bool get anyPrivileged => containers.any((c) => c.privileged);

  bool get usesHostNamespaces => hostNetwork || hostPid || hostIpc;
}

/// Pod spec map (`spec` of a Pod, `spec.template.spec` of a controller).
K8sPodConfig parsePodSpec(
  Map<String, dynamic> spec, {
  bool ownedByController = false,
}) {
  final refs = _RefSet();
  final containers = <K8sContainerConfig>[
    for (final c in _list(spec['initContainers']))
      _container(c, refs, init: true),
    for (final c in _list(spec['containers'])) _container(c, refs),
  ];
  final claims = <String>[];
  for (final v in _list(spec['volumes'])) {
    final pvc = _map(v['persistentVolumeClaim'])['claimName'];
    if (pvc is String && pvc.isNotEmpty && !claims.contains(pvc)) {
      claims.add(pvc);
    }
    final cm = _map(v['configMap']);
    if (cm['name'] is String) {
      refs.add(K8sConfigRef(
        kind: 'ConfigMap',
        name: cm['name'] as String,
        optional: cm['optional'] == true,
      ));
    }
    final secret = _map(v['secret']);
    if (secret['secretName'] is String) {
      refs.add(K8sConfigRef(
        kind: 'Secret',
        name: secret['secretName'] as String,
        optional: secret['optional'] == true,
      ));
    }
    for (final source in _list(_map(v['projected'])['sources'])) {
      final pcm = _map(source['configMap']);
      if (pcm['name'] is String) {
        refs.add(K8sConfigRef(
          kind: 'ConfigMap',
          name: pcm['name'] as String,
          optional: pcm['optional'] == true,
        ));
      }
      final ps = _map(source['secret']);
      if (ps['name'] is String) {
        refs.add(K8sConfigRef(
          kind: 'Secret',
          name: ps['name'] as String,
          optional: ps['optional'] == true,
        ));
      }
    }
  }
  for (final s in _list(spec['imagePullSecrets'])) {
    if (s['name'] is String) {
      // A missing pull secret only matters for private images; never fatal.
      refs.add(K8sConfigRef(
        kind: 'Secret',
        name: s['name'] as String,
        optional: true,
      ));
    }
  }
  return K8sPodConfig(
    containers: containers,
    refs: refs.refs,
    serviceAccount: spec['serviceAccountName'] as String? ??
        spec['serviceAccount'] as String? ??
        'default',
    hostNetwork: spec['hostNetwork'] == true,
    hostPid: spec['hostPID'] == true,
    hostIpc: spec['hostIPC'] == true,
    ownedByController: ownedByController,
    claims: claims,
  );
}

K8sContainerConfig _container(
  Map<String, dynamic> raw,
  _RefSet refs, {
  bool init = false,
}) {
  for (final e in _list(raw['envFrom'])) {
    final cm = _map(e['configMapRef']);
    if (cm['name'] is String) {
      refs.add(K8sConfigRef(
        kind: 'ConfigMap',
        name: cm['name'] as String,
        optional: cm['optional'] == true,
      ));
    }
    final s = _map(e['secretRef']);
    if (s['name'] is String) {
      refs.add(K8sConfigRef(
        kind: 'Secret',
        name: s['name'] as String,
        optional: s['optional'] == true,
      ));
    }
  }
  for (final e in _list(raw['env'])) {
    final from = _map(e['valueFrom']);
    final cm = _map(from['configMapKeyRef']);
    if (cm['name'] is String) {
      refs.add(K8sConfigRef(
        kind: 'ConfigMap',
        name: cm['name'] as String,
        optional: cm['optional'] == true,
      ));
    }
    final s = _map(from['secretKeyRef']);
    if (s['name'] is String) {
      refs.add(K8sConfigRef(
        kind: 'Secret',
        name: s['name'] as String,
        optional: s['optional'] == true,
      ));
    }
  }
  final resources = _map(raw['resources']);
  final requests = _map(resources['requests']);
  final limits = _map(resources['limits']);
  final security = _map(raw['securityContext']);
  return K8sContainerConfig(
    name: raw['name'] as String? ?? '',
    image: raw['image'] as String? ?? '',
    cpuRequest: '${requests['cpu'] ?? ''}',
    memoryRequest: '${requests['memory'] ?? ''}',
    cpuLimit: '${limits['cpu'] ?? ''}',
    memoryLimit: '${limits['memory'] ?? ''}',
    readinessProbe: raw['readinessProbe'] is Map,
    livenessProbe: raw['livenessProbe'] is Map,
    privileged: security['privileged'] == true,
    init: init,
  );
}

List<Map<String, dynamic>> _list(Object? v) {
  if (v is! List) {
    return const [];
  }
  return [
    for (final item in v)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return const {};
}
