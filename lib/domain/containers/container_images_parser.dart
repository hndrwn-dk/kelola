import 'dart:convert';

import 'package:kelola/domain/containers/container_images.dart';

class ContainerImagesParser {
  const ContainerImagesParser();

  ContainerImageInventory parse(String stdout, {String engine = 'docker'}) {
    final imageBody = _section(stdout, 'IMAGES');
    final dfBody = _section(stdout, 'DF');
    final images = _parseImages(imageBody, engine)
      ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final reclaim = _parseReclaimable(dfBody);
    return ContainerImageInventory(
      images: images,
      reclaimableBytes: reclaim.$1,
      reclaimableLabel: reclaim.$2,
      engine: engine,
    );
  }

  List<ContainerImage> _parseImages(String body, String engine) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return [];
    }
    if (trimmed.startsWith('[')) {
      return _parsePodmanArray(trimmed);
    }
    final out = <ContainerImage>[];
    for (final line in trimmed.split('\n')) {
      final t = line.trim();
      if (!t.startsWith('{')) {
        continue;
      }
      try {
        final decoded = jsonDecode(t);
        if (decoded is Map) {
          final img = _fromMap(decoded.cast<String, dynamic>(), engine);
          if (img != null) {
            out.add(img);
          }
        }
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  List<ContainerImage> _parsePodmanArray(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      final out = <ContainerImage>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final img = _fromMap(item.cast<String, dynamic>(), 'podman');
        if (img != null) {
          out.add(img);
        }
      }
      return out;
    } on FormatException {
      return [];
    }
  }

  ContainerImage? _fromMap(Map<String, dynamic> map, String engine) {
    final id = (map['ID'] ?? map['Id'] ?? '').toString();
    if (id.isEmpty) {
      return null;
    }
    var repository = (map['Repository'] ?? map['Names'] ?? '').toString();
    final names = map['Names'];
    if (names is List && names.isNotEmpty) {
      repository = names.first.toString();
    }
    final tag = (map['Tag'] ?? '').toString();
    final sizeRaw = map['Size'] ?? map['VirtualSize'] ?? '';
    final sizeLabel = sizeRaw is num ? _labelFromBytes(sizeRaw.toInt()) : sizeRaw.toString();
    final sizeBytes = sizeRaw is num
        ? sizeRaw.toInt()
        : parseByteSize(sizeRaw.toString());
    return ContainerImage(
      id: id,
      repository: repository,
      tag: tag,
      sizeLabel: sizeLabel,
      sizeBytes: sizeBytes,
    );
  }

  (int, String) _parseReclaimable(String df) {
    for (final line in df.split('\n')) {
      final t = line.trim();
      if (!t.toLowerCase().startsWith('images')) {
        continue;
      }
      final sizes = RegExp(r'[\d.]+[KMGT]i?B', caseSensitive: false)
          .allMatches(t)
          .map((m) => m.group(0)!)
          .toList();
      if (sizes.isEmpty) {
        return (0, '');
      }
      final label = sizes.last;
      return (parseByteSize(label), label);
    }
    return (0, '');
  }

  String _labelFromBytes(int bytes) {
    if (bytes >= 1000000000) {
      return '${(bytes / 1000000000).toStringAsFixed(1)}GB';
    }
    if (bytes >= 1000000) {
      return '${(bytes / 1000000).toStringAsFixed(1)}MB';
    }
    return '${bytes}B';
  }

  String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return stdout.trim();
    }
    final start = i + marker.length;
    final next = RegExp(r'^---[A-Z_]+---\s*$', multiLine: true)
        .firstMatch(stdout.substring(start));
    final end = next == null ? stdout.length : start + next.start;
    return stdout.substring(start, end).replaceAll('\r', '').trim();
  }
}
