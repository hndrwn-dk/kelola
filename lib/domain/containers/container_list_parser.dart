import 'dart:convert';

import 'package:kelola/domain/containers/container_row.dart';

class ContainerListParser {
  const ContainerListParser();

  ContainerInventory parse(String stdout) {
    final engineBlock = _section(stdout, 'ENGINE');
    final engines = engineBlock
        .split(RegExp(r'\s+'))
        .map((e) => e.split('/').last.trim())
        .where((e) => e.isNotEmpty && e != 'none')
        .toList();
    final engine = engines.isEmpty
        ? _section(stdout, 'ENGINE').trim().split('\n').first.trim()
        : engines.first;
    final pods = _parsePods(_section(stdout, 'PODS'), engine);
    final dockerDenied = stdout.contains('---DOCKER_DENIED---');
    final body = _section(stdout, 'PS');
    final dockerRows = _parsePs(body, _dockerEngine(engines, engine));
    return ContainerInventory(
      rows: [...pods, ...dockerRows],
      engines: engines,
      dockerDenied: dockerDenied,
    );
  }

  String _dockerEngine(List<String> engines, String fallback) {
    for (final e in engines) {
      if (e == 'docker' || e == 'podman' || e == 'crictl') {
        return e;
      }
    }
    return fallback;
  }

  List<ContainerRow> _parsePs(String body, String engine) {
    if (body.isEmpty) {
      return const [];
    }
    final trimmed = body.trim();
    if (trimmed.startsWith('{') && trimmed.contains('"containers"')) {
      return _parseCrictl(trimmed, engine == 'none' ? 'crictl' : engine);
    }
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

  List<ContainerRow> _parsePods(String raw, String engine) {
    final out = <ContainerRow>[];
    final label = engine == 'kubectl' ? 'k8s' : (engine == 'k3s' ? 'k3s' : 'k8s');
    for (final line in raw.split('\n')) {
      final parts = line.trim().split('\t');
      if (parts.length < 3) {
        continue;
      }
      final ns = parts[0];
      final name = parts[1];
      if (ns.isEmpty || name.isEmpty || ns == 'none') {
        continue;
      }
      final phase = parts[2];
      final image = parts.length > 3 ? parts.sublist(3).join('\t') : '';
      out.add(
        ContainerRow(
          id: '$ns/$name',
          names: name,
          namespace: ns,
          image: image,
          state: phase.toLowerCase() == 'running' ? 'running' : phase,
          status: phase,
          engine: label,
        ),
      );
    }
    return out;
  }

  List<ContainerRow> _parseCrictl(String raw, String engine) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const [];
      }
      final list = decoded['containers'];
      if (list is! List) {
        return const [];
      }
      final out = <ContainerRow>[];
      for (final item in list) {
        if (item is! Map) {
          continue;
        }
        final map = item.cast<String, dynamic>();
        final id = (map['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }
        final meta = map['metadata'];
        var name = '';
        if (meta is Map) {
          name = (meta['name'] ?? '').toString();
        }
        var image = '';
        final img = map['image'];
        if (img is Map) {
          image = (img['image'] ?? img['name'] ?? '').toString();
        }
        final state = (map['state'] ?? '').toString();
        out.add(
          ContainerRow(
            id: id,
            names: name,
            image: image,
            state: state.toLowerCase().replaceFirst('container_', ''),
            status: state,
            engine: engine,
          ),
        );
      }
      return out;
    } on FormatException {
      return const [];
    }
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
    var ports = (map['Ports'] ?? '').toString();
    final portsRaw = map['Ports'];
    if (portsRaw is List) {
      ports = portsRaw.map((e) => e.toString()).join(', ');
    }
    return ContainerRow(
      id: id,
      names: names,
      image: (map['Image'] ?? '').toString(),
      state: (map['State'] ?? '').toString(),
      status: (map['Status'] ?? '').toString(),
      ports: ports,
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
