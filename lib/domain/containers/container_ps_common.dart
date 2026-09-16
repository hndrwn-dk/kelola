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

/// Host mappings, including the bind address when the engine reported one.
String formatPublishedPorts(dynamic raw) {
  return parsePublishedPorts(raw).map((p) => p.label).join(', ');
}

List<PublishedPort> parsePublishedPorts(dynamic raw) {
  if (raw == null) {
    return const [];
  }
  final seen = <String>{};
  final out = <PublishedPort>[];
  void add(PublishedPort port) {
    if (port.label.isEmpty || !seen.add(port.label)) {
      return;
    }
    out.add(port);
  }

  if (raw is List) {
    for (final item in raw) {
      if (item is Map) {
        add(_fromPortMap(item));
      } else {
        for (final port in _fromDockerPortString(item.toString())) {
          add(port);
        }
      }
    }
    return out;
  }
  for (final port in _fromDockerPortString(raw.toString())) {
    add(port);
  }
  return out;
}

PublishedPort _fromPortMap(Map<dynamic, dynamic> item) {
  final host = _asInt(
    item['host_port'] ?? item['HostPort'] ?? item['PublicPort'],
  );
  final cont = _asInt(
    item['container_port'] ?? item['ContainerPort'] ?? item['PrivatePort'],
  );
  final bind = (item['host_ip'] ?? item['HostIp'] ?? item['IP'] ?? '')
      .toString()
      .trim();
  return PublishedPort(bind: bind, hostPort: host, containerPort: cont);
}

int? _asInt(dynamic v) {
  if (v is int) {
    return v;
  }
  return int.tryParse('${v ?? ''}');
}

List<PublishedPort> _fromDockerPortString(String raw) {
  final mapped = RegExp(
    r'(?:\[([0-9a-fA-F:]+)\]|(\d+\.\d+\.\d+\.\d+)|([0-9a-fA-F:]*)):(\d+)->(\d+)',
  );
  final out = <PublishedPort>[];
  for (final m in mapped.allMatches(raw)) {
    final bind = (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
    out.add(
      PublishedPort(
        bind: bind,
        hostPort: int.parse(m.group(4)!),
        containerPort: int.parse(m.group(5)!),
      ),
    );
  }
  if (out.isNotEmpty) {
    return out;
  }
  final lone = RegExp(r'(\d+)/');
  for (final m in lone.allMatches(raw)) {
    out.add(PublishedPort(containerPort: int.parse(m.group(1)!)));
  }
  return out;
}

ContainerRow rowFromPsMap(Map<String, dynamic> map, String engine) {
  final id = (map['ID'] ?? map['Id'] ?? '').toString();
  final names = firstName(map['Names'] ?? map['Name']);
  final status = (map['Status'] ?? '').toString();
  final labels = labelsFromJson(map['Labels'] ?? map['labels']);
  final portsRaw = map['Ports'] ?? map['ports'] ?? '';
  final bindings = parsePublishedPorts(portsRaw);
  return ContainerRow(
    id: id,
    names: names,
    image: (map['Image'] ?? map['ImageName'] ?? '').toString(),
    state: (map['State'] ?? '').toString(),
    status: status,
    ports: portsRaw is List ? portsRaw.join(', ') : portsRaw.toString(),
    publishedPorts: bindings.map((p) => p.label).join(', '),
    portBindings: bindings,
    engine: engine,
    composeProject: composeProjectFromLabels(labels),
    exitCode: exitCodeFrom(status, map['ExitCode'] ?? map['ExitCodeRaw']),
    labels: labels,
  );
}
