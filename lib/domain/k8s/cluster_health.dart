import 'package:kelola/design/kelola_theme.dart';

class ClusterNodeMembership {
  const ClusterNodeMembership({
    required this.name,
    required this.ready,
    required this.kubeletVersion,
    required this.containerRuntime,
    this.controlPlane = false,
  });

  final String name;
  final bool ready;
  final String kubeletVersion;
  final String containerRuntime;
  final bool controlPlane;

  String get membershipLabel {
    final parts = <String>[
      ready ? 'Ready' : 'NotReady',
      if (kubeletVersion.isNotEmpty) 'kubelet',
      if (containerRuntime.isNotEmpty) _runtimeShort(containerRuntime),
    ];
    return parts.join(' · ');
  }
}

String _runtimeShort(String raw) {
  final cut = raw.split('://').first.trim();
  return cut.isEmpty ? raw : cut;
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
  });

  final bool apiReachable;
  final int controlPlaneReady;
  final int controlPlaneDesired;
  final ClusterNodeMembership? thisHost;
  final bool thisHostMatched;

  /// null = unknown / not observed on this probe.
  final bool? coreDnsReady;
  final bool missingKubectl;

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
    );
  }
}
