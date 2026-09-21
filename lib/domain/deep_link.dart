class KelolaLink {
  const KelolaLink({
    this.hostId,
    this.incident = false,
    this.unitName,
    this.tunnel = false,
  });

  final String? hostId;
  final bool incident;
  final String? unitName;
  final bool tunnel;
}

KelolaLink parseKelolaLink(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri != null &&
      uri.scheme == 'kelola' &&
      uri.host == 'host' &&
      uri.pathSegments.isNotEmpty) {
    return _fromSegments(uri.pathSegments);
  }
  final parts = raw.split('/').where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2 && parts.first == 'host') {
    return _fromSegments(parts.sublist(1));
  }
  return const KelolaLink();
}

KelolaLink _fromSegments(List<String> segments) {
  final id = segments.first;
  if (id.isEmpty) {
    return const KelolaLink();
  }
  if (segments.length >= 2 && segments[1] == 'incident') {
    return KelolaLink(hostId: id, incident: true);
  }
  if (segments.length >= 2 && segments[1] == 'tunnel') {
    return KelolaLink(hostId: id, tunnel: true);
  }
  if (segments.length >= 3 && segments[1] == 'unit') {
    final name = segments[2];
    if (name.isEmpty) {
      return KelolaLink(hostId: id);
    }
    return KelolaLink(hostId: id, unitName: name);
  }
  return KelolaLink(hostId: id);
}
