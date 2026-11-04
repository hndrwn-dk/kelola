import 'package:kelola/design/kelola_theme.dart';

/// M48: Machine Config Daemon state from the node annotation
/// `machineconfiguration.openshift.io/state`. Null off OpenShift.
enum McdState { done, working, degraded }

class ClusterNodeMembership {
  const ClusterNodeMembership({
    required this.name,
    required this.ready,
    required this.kubeletVersion,
    required this.containerRuntime,
    this.controlPlane = false,
    this.pressures = const [],
    this.mcdState,
    this.updatePending = false,
    this.mcdReason = '',
    this.roles = const [],
    this.labels = const {},
  });

  final String name;
  final bool ready;
  final String kubeletVersion;
  final String containerRuntime;
  final bool controlPlane;

  /// Node conditions other than Ready that are currently True, e.g.
  /// `DiskPressure`, `MemoryPressure`, `PIDPressure`, `NetworkUnavailable`.
  final List<String> pressures;

  /// M48. Null when the node carries no MCD annotation (not OpenShift).
  final McdState? mcdState;

  /// `currentConfig` differs from `desiredConfig`.
  final bool updatePending;

  /// MCD `reason` annotation; shown when [mcdState] is degraded.
  final String mcdReason;

  /// From `node-role.kubernetes.io/*`: master, control-plane, worker, infra.
  final List<String> roles;

  /// Node labels, kept so a MachineConfigPool's `nodeSelector` can be
  /// matched against nodes already read (no extra call).
  final Map<String, String> labels;

  /// `Ready · Done`, `Ready · Working (update pending)`,
  /// `Ready · Degraded: <reason>`. Plain `Ready` off OpenShift.
  String get mcdLabel {
    final parts = <String>[ready ? 'Ready' : 'NotReady'];
    final state = mcdState;
    if (state != null) {
      parts.add(switch (state) {
        McdState.done => updatePending ? 'Done (update pending)' : 'Done',
        McdState.working =>
          updatePending ? 'Working (update pending)' : 'Working',
        McdState.degraded => mcdReason.trim().isEmpty
            ? 'Degraded'
            : 'Degraded: ${mcdReason.trim()}',
      });
    } else if (updatePending) {
      parts.add('update pending');
    }
    return parts.join(' · ');
  }

  /// Node row meta: `master, worker · Ready · Done`.
  String get nodeRowMeta {
    return [
      if (roles.isNotEmpty) roles.join(', '),
      mcdLabel,
      if (pressures.isNotEmpty) pressures.join(', '),
    ].join(' · ');
  }

  HealthStatus get nodeHealth {
    if (!ready || mcdState == McdState.degraded) {
      return HealthStatus.failed;
    }
    if (pressures.isNotEmpty) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }

  /// `Ready · kubelet v1.31.0 · containerd 1.7.22`
  String get membershipLabel {
    final parts = <String>[
      ready ? 'Ready' : 'NotReady',
      if (kubeletVersion.isNotEmpty) 'kubelet $kubeletVersion',
      if (containerRuntime.isNotEmpty) runtimeLabel(containerRuntime),
    ];
    return parts.join(' · ');
  }
}

/// `containerd://1.7.22` → `containerd 1.7.22`.
String runtimeLabel(String raw) {
  final parts = raw.split('://');
  final name = parts.first.trim();
  if (parts.length < 2) {
    return name.isEmpty ? raw : name;
  }
  final version = parts.sublist(1).join('://').trim();
  return version.isEmpty ? name : '$name $version';
}

class ClusterHealth {
  const ClusterHealth({
    required this.apiReachable,
    required this.controlPlaneReady,
    required this.controlPlaneDesired,
    this.thisHost,
    this.thisHostMatched = false,
    this.coreDnsReady,
    this.missingKubectl = false,
    this.nodes = const [],
    this.isOpenShift,
    this.authExpired = false,
    this.kubeContext = '',
  });

  final bool apiReachable;
  final int controlPlaneReady;
  final int controlPlaneDesired;
  final ClusterNodeMembership? thisHost;
  final bool thisHostMatched;

  /// null = unknown / not observed on this probe.
  final bool? coreDnsReady;
  final bool missingKubectl;

  /// Every node `kubectl get nodes` returned (control plane + workers).
  final List<ClusterNodeMembership> nodes;

  /// M48: the API serves `config.openshift.io/v1`. Null = unknown (section
  /// missing or junk). Not a host fact: it follows the kubeconfig context.
  final bool? isOpenShift;

  /// M48: readyz failed and the CLI said the login is no longer valid
  /// (`oc login` token expired). The API answered, so this is never
  /// "API down".
  final bool authExpired;

  /// `config current-context` on the host. Empty when unknown.
  final String kubeContext;

  /// Nodes whose MCD state is Degraded (OpenShift only).
  List<ClusterNodeMembership> get mcdDegradedNodes => [
        for (final n in nodes)
          if (n.mcdState == McdState.degraded) n,
      ];

  int get nodesTotal => nodes.length;

  int get nodesReady => nodes.where((n) => n.ready).length;

  List<String> get notReadyNodes => [
        for (final n in nodes)
          if (!n.ready) n.name,
      ];

  /// `node-a: DiskPressure` for every node with a True pressure condition.
  List<String> get pressuredNodes => [
        for (final n in nodes)
          if (n.pressures.isNotEmpty) '${n.name}: ${n.pressures.join(', ')}',
      ];

  String get nodesLabel {
    if (nodesTotal == 0) {
      return 'unknown';
    }
    return '$nodesReady/$nodesTotal Ready';
  }

  HealthStatus get overall {
    if (missingKubectl) {
      return HealthStatus.unknown;
    }
    // A distinct state, shown on its own; not a dead API.
    if (authExpired) {
      return HealthStatus.unknown;
    }
    if (!apiReachable) {
      return HealthStatus.failed;
    }
    if (thisHostMatched && thisHost != null && !thisHost!.ready) {
      return HealthStatus.warning;
    }
    if (!thisHostMatched) {
      return HealthStatus.warning;
    }
    if (coreDnsReady == false) {
      return HealthStatus.warning;
    }
    if (controlPlaneDesired > 0 && controlPlaneReady < controlPlaneDesired) {
      return HealthStatus.warning;
    }
    if (nodesReady < nodesTotal || pressuredNodes.isNotEmpty) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }

  String get controlPlaneLabel {
    if (controlPlaneDesired <= 0) {
      return 'unknown';
    }
    return '$controlPlaneReady/$controlPlaneDesired Ready';
  }

  ClusterHealth withCoreDns(bool? ready) {
    return ClusterHealth(
      apiReachable: apiReachable,
      controlPlaneReady: controlPlaneReady,
      controlPlaneDesired: controlPlaneDesired,
      thisHost: thisHost,
      thisHostMatched: thisHostMatched,
      coreDnsReady: ready,
      missingKubectl: missingKubectl,
      nodes: nodes,
      isOpenShift: isOpenShift,
      authExpired: authExpired,
      kubeContext: kubeContext,
    );
  }
}
