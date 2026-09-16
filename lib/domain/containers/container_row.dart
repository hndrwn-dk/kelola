class ContainerRow {
  const ContainerRow({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
    this.ports = '',
    this.publishedPorts = '',
    this.portBindings = const [],
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
  final List<PublishedPort> portBindings;
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

/// One published mapping. [bind] is the address the host port is bound to,
/// kept as reported — never rewritten to `0.0.0.0`.
class PublishedPort {
  const PublishedPort({
    this.bind = '',
    this.hostPort,
    this.containerPort,
  });

  final String bind;
  final int? hostPort;
  final int? containerPort;

  bool get loopback {
    final b = bind.toLowerCase();
    return b == '::1' || b == 'localhost' || b.startsWith('127.');
  }

  bool get allInterfaces {
    return bind == '0.0.0.0' || bind == '::' || bind == '*';
  }

  String get label {
    final pair = publishedPortPair(hostPort, containerPort);
    if (bind.isEmpty) {
      return pair;
    }
    final host = bind.contains(':') ? '[$bind]' : bind;
    if (pair.isEmpty) {
      return host;
    }
    return '$host:$pair';
  }
}

String publishedPortPair(int? host, int? cont) {
  if (host == null && cont == null) {
    return '';
  }
  if (host == null) {
    return '$cont';
  }
  if (cont == null || host == cont) {
    return '$host';
  }
  return '$host\u2192$cont';
}
