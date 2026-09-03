class KelolaLink {
  const KelolaLink({this.hostId, this.incident = false});

  final String? hostId;
  final bool incident;
}

KelolaLink parseKelolaLink(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) {
    return const KelolaLink();
  }
  if (uri.scheme == 'kelola' &&
      uri.host == 'host' &&
      uri.pathSegments.isNotEmpty) {
    return KelolaLink(
      hostId: uri.pathSegments.first,
      incident: uri.pathSegments.length >= 2 &&
          uri.pathSegments[1] == 'incident',
    );
  }
  final parts = raw.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2 && parts.first == 'host') {
    return KelolaLink(
      hostId: parts[1],
      incident: parts.length >= 3 && parts[2] == 'incident',
    );
  }
  return const KelolaLink();
}
