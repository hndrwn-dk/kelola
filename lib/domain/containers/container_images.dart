class ContainerImage {
  const ContainerImage({
    required this.id,
    required this.repository,
    this.tag = '',
    this.sizeLabel = '',
    this.sizeBytes = 0,
  });

  final String id;
  final String repository;
  final String tag;
  final String sizeLabel;
  final int sizeBytes;
}

class ContainerImageInventory {
  const ContainerImageInventory({
    required this.images,
    this.reclaimableBytes = 0,
    this.reclaimableLabel = '',
    this.engine = 'docker',
  });

  final List<ContainerImage> images;
  final int reclaimableBytes;
  final String reclaimableLabel;
  final String engine;
}

int parseByteSize(String raw) {
  final t = raw.trim();
  final m =
      RegExp(r'^([\d.]+)\s*([KMGT]i?B)$', caseSensitive: false).firstMatch(t);
  if (m == null) {
    return int.tryParse(t) ?? 0;
  }
  final n = double.tryParse(m.group(1)!) ?? 0;
  final u = m.group(2)!.toUpperCase();
  final binary = u.contains('I');
  final base = binary ? 1024.0 : 1000.0;
  final exp = switch (u[0]) {
    'K' => 1,
    'M' => 2,
    'G' => 3,
    'T' => 4,
    _ => 0,
  };
  return (n * _pow(base, exp)).round();
}

double _pow(double base, int exp) {
  var out = 1.0;
  for (var i = 0; i < exp; i++) {
    out *= base;
  }
  return out;
}
