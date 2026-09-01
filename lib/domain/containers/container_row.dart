class ContainerRow {
  const ContainerRow({
    required this.id,
    required this.names,
    required this.image,
    required this.state,
    required this.status,
    this.ports = '',
    this.engine = 'docker',
  });

  final String id;
  final String names;
  final String image;
  final String state;
  final String status;
  final String ports;
  final String engine;

  bool get running => state.toLowerCase() == 'running';
}
