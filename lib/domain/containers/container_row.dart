class ContainerRow {
  const ContainerRow({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
    this.ports = '',
    this.publishedPorts = '',
    this.engine = 'docker',
    this.namespace = '',
    this.composeProject = '',
    this.exitCode,
    this.labels = const {},
  });

  final String id;
  final String names;
  final String image;
  final String state;
  final String status;
  final String ports;
  final String publishedPorts;
  final String engine;
  final String namespace;
  final String composeProject;
  final int? exitCode;
  final Map<String, String> labels;

  bool get running {
    final s = state.toLowerCase();
    return s == 'running' || s == 'container_running';
  }

  String get title {
    if (namespace.isNotEmpty) {
      return '$namespace/$names';
    }
    if (names.isNotEmpty) {
      return names;
    }
    return id;
  }
}

class ContainerInventory {
  const ContainerInventory({
    required this.rows,
    this.engines = const [],
    this.dockerDenied = false,
    this.podmanDenied = false,
    this.podmanSocketDenied = false,
  });

  final List<ContainerRow> rows;
  final List<String> engines;
  final bool dockerDenied;

  /// Podman is installed, but neither the user store nor a passwordless
  /// root store could be listed. An empty user store is not this.
  final bool podmanDenied;

  /// System socket exists, but this SSH user cannot read it. Same shape
  /// as the docker group: membership, then a new session.
  final bool podmanSocketDenied;
}
