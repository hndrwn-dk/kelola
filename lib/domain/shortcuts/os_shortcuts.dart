class OsShortcut {
  const OsShortcut({
    required this.id,
    required this.label,
    required this.uri,
  });

  final String id;
  final String label;
  final String uri;

  Map<String, String> toMap() => {
        'id': id,
        'label': label,
        'uri': uri,
      };
}

List<OsShortcut> buildOsShortcuts({
  required String? lastHostId,
  required bool lastHostHasTunnelTarget,
}) {
  final id = lastHostId;
  if (id == null || id.isEmpty) {
    return const [];
  }
  final items = <OsShortcut>[
    OsShortcut(
      id: 'last_host',
      label: 'Last host',
      uri: 'kelola://host/$id',
    ),
    OsShortcut(
      id: 'incident',
      label: 'Incident',
      uri: 'kelola://host/$id/incident',
    ),
  ];
  if (lastHostHasTunnelTarget) {
    items.add(
      OsShortcut(
        id: 'last_tunnel',
        label: 'Last tunnel',
        uri: 'kelola://host/$id/tunnel',
      ),
    );
  }
  return items;
}
