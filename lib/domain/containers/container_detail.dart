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
