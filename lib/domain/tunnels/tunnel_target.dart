enum TunnelScheme {
  http,
  https;

  String get value => name;

  static TunnelScheme? parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'http':
        return TunnelScheme.http;
      case 'https':
        return TunnelScheme.https;
      default:
        return null;
    }
  }
}

class TunnelTarget {
  const TunnelTarget({
    required this.id,
    required this.hostId,
    required this.label,
    required this.remoteHost,
    required this.remotePort,
    required this.scheme,
    required this.path,
  });

  final String id;
  final String hostId;
  final String label;
  final String remoteHost;
  final int remotePort;
  final TunnelScheme scheme;
  final String path;
}
