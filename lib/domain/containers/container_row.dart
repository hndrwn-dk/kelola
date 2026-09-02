class ContainerRow {
  const ContainerRow({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
    this.ports = '',
    this.engine = 'docker',
    this.namespace = '',
  });

  final String id;
  final String names;
  final String image;
  final String state;
  final String status;
  final String ports;
  final String engine;
  final String namespace;

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
  });

  final List<ContainerRow> rows;
  final List<String> engines;
  final bool dockerDenied;
}
