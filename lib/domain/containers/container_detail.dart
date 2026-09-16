class ContainerDetail {
  const ContainerDetail({
    required this.name,
    this.env = const [],
    this.mounts = const [],
    this.networks = const [],
    this.restartPolicy = '',
    this.cpuPerc = '',
    this.memUsage = '',
    this.logs = '',
  });

  final String name;
  final List<String> env;
  final List<String> mounts;
  final List<String> networks;
  final String restartPolicy;
  final String cpuPerc;
  final String memUsage;
  final String logs;
}

/// False when inspect returned no payload. The detail screen treats that
/// as empty and keeps actions hidden.
bool containerInspectArrived(ContainerDetail detail) {
  return detail.name.isNotEmpty ||
      detail.env.isNotEmpty ||
      detail.mounts.isNotEmpty ||
      detail.networks.isNotEmpty ||
      detail.restartPolicy.isNotEmpty ||
      detail.cpuPerc.isNotEmpty ||
      detail.memUsage.isNotEmpty ||
      detail.logs.trim().isNotEmpty;
}
