import 'dart:convert';

import 'package:kelola/domain/containers/container_row.dart';

class ContainerListParser {
  const ContainerListParser();

  List<ContainerRow> parse(String stdout) {
    final engine = _section(stdout, 'ENGINE').trim().split('\n').first.trim();
    final body = _section(stdout, 'PS');
    if (engine == 'none' || body.isEmpty) {
      return const [];
    }
    final trimmed = body.trim();
    if (trimmed.startsWith('[')) {
      return _parseArray(trimmed, engine);
    }
    final out = <ContainerRow>[];
    for (final line in trimmed.split('\n')) {
      final row = _parseObject(line.trim(), engine);
      if (row != null) {
        out.add(row);
      }
    }
    return out;
  }

  List<ContainerRow> _parseArray(String raw, String engine) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      final out = <ContainerRow>[];
      for (final item in decoded) {
        if (item is Map) {
          final row = _fromMap(item.cast<String, dynamic>(), engine);
          if (row != null) {
            out.add(row);
          }
        }
      }
      return out;
    } on FormatException {
      return const [];
    }
  }

  ContainerRow? _parseObject(String line, String engine) {
    if (line.isEmpty || line[0] != '{') {
      return null;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return null;
      }
      return _fromMap(decoded.cast<String, dynamic>(), engine);
    } on FormatException {
      return null;
    }
  }

  ContainerRow? _fromMap(Map<String, dynamic> map, String engine) {
    final id = (map['ID'] ?? map['Id'] ?? '').toString();
    if (id.isEmpty) {
      return null;
    }
    var names = (map['Names'] ?? map['Name'] ?? '').toString();
    final namesRaw = map['Names'];
    if (namesRaw is List) {
      names = namesRaw.map((e) => e.toString()).join(', ');
    }
    names = names.replaceFirst(RegExp(r'^/'), '');
    return ContainerRow(
      id: id,
      names: names,
      image: (map['Image'] ?? '').toString(),
      state: (map['State'] ?? '').toString(),
      status: (map['Status'] ?? '').toString(),
      ports: (map['Ports'] ?? '').toString(),
      engine: engine,
    );
  }

  String _section(String stdout, String name) {
    final re = RegExp(r'^---([A-Z_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      if (matches[i].group(1) != name) {
        continue;
      }
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      return stdout.substring(start, end).replaceAll('\r', '').trim();
    }
    return '';
  }
}
