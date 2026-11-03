import 'package:kelola/design/kelola_theme.dart';

class ClusterNodeMembership {
  const ClusterNodeMembership({
    required this.name,
    required this.ready,
    required this.kubeletVersion,
    required this.containerRuntime,
    this.controlPlane = false,
    this.pressures = const [],
  });

  final String name;
  final bool ready;
  final String kubeletVersion;
  final String containerRuntime;
  final bool controlPlane;

  /// Node conditions other than Ready that are currently True, e.g.
  /// `DiskPressure`, `MemoryPressure`, `PIDPressure`, `NetworkUnavailable`.
  final List<String> pressures;

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
    );
  }
}
