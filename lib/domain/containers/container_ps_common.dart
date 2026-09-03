import 'package:kelola/domain/containers/container_row.dart';

String composeProjectFromLabels(Map<String, String> labels) {
  return labels['com.docker.compose.project'] ??
      labels['io.podman.compose.project'] ??
      '';
}

Map<String, String> parseLabelString(String raw) {
  final out = <String, String>{};
  if (raw.trim().isEmpty) {
    return out;
  }
  for (final part in raw.split(',')) {
    final eq = part.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    out[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }
  return out;
}

Map<String, String> labelsFromJson(dynamic raw) {
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  if (raw is String) {
    return parseLabelString(raw);
  }
  return const {};
}

int? exitCodeFrom(String status, dynamic raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  final parsed = int.tryParse('${raw ?? ''}');
  if (parsed != null) {
    return parsed;
  }
  final m = RegExp(r'Exited \((\d+)\)').firstMatch(status);
  return m == null ? null : int.parse(m.group(1)!);
}

String firstName(dynamic raw) {
  if (raw is List && raw.isNotEmpty) {
    return raw.first.toString().replaceFirst(RegExp(r'^/'), '');
  }
  return raw?.toString().replaceFirst(RegExp(r'^/'), '') ?? '';
}

/// Host mappings as `32787→32400`, or `80` when host equals container.
String formatPublishedPorts(dynamic raw) {
  if (raw == null) {
    return '';
  }
  if (raw is List) {
    final bits = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is Map) {
        final host = _asInt(item['host_port'] ?? item['HostPort']);
        final cont = _asInt(
          item['container_port'] ?? item['ContainerPort'] ?? item['PrivatePort'],
        );
        final label = _portPair(host, cont);
        if (label.isNotEmpty && seen.add(label)) {
          bits.add(label);
        }
      } else {
        for (final label in _fromDockerPortString(item.toString())) {
          if (seen.add(label)) {
            bits.add(label);
          }
        }
      }
    }
    return bits.join(', ');
  }
  return _fromDockerPortString(raw.toString()).join(', ');
}

int? _asInt(dynamic v) {
  if (v is int) {
    return v;
  }
  return int.tryParse('${v ?? ''}');
}

String _portPair(int? host, int? cont) {
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

List<String> _fromDockerPortString(String raw) {
  final seen = <String>{};
  final out = <String>[];
  final mapped = RegExp(r'(?:[\d.]+|\[?[0-9a-fA-F:]+\]?)?:(\d+)->(\d+)');
  for (final m in mapped.allMatches(raw)) {
    final label = _portPair(int.parse(m.group(1)!), int.parse(m.group(2)!));
    if (label.isNotEmpty && seen.add(label)) {
      out.add(label);
    }
  }
  if (out.isNotEmpty) {
    return out;
  }
  final lone = RegExp(r'(\d+)/');
  for (final m in lone.allMatches(raw)) {
    final label = m.group(1)!;
    if (seen.add(label)) {
      out.add(label);
    }
  }
  return out;
}

ContainerRow rowFromPsMap(Map<String, dynamic> map, String engine) {
  final id = (map['ID'] ?? map['Id'] ?? '').toString();
  final names = firstName(map['Names'] ?? map['Name']);
  final status = (map['Status'] ?? '').toString();
  final labels = labelsFromJson(map['Labels'] ?? map['labels']);
  final portsRaw = map['Ports'] ?? map['ports'] ?? '';
  return ContainerRow(
    id: id,
    names: names,
    image: (map['Image'] ?? map['ImageName'] ?? '').toString(),
    state: (map['State'] ?? '').toString(),
    status: status,
    ports: portsRaw is List ? portsRaw.join(', ') : portsRaw.toString(),
    publishedPorts: formatPublishedPorts(portsRaw),
    engine: engine,
    composeProject: composeProjectFromLabels(labels),
    exitCode: exitCodeFrom(status, map['ExitCode'] ?? map['ExitCodeRaw']),
    labels: labels,
  );
}
