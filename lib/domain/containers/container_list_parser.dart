import 'dart:convert';

import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/containers/docker_ps_parser.dart';
import 'package:kelola/domain/containers/podman_ps_parser.dart';

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
        ? engineBlock.trim().split('\n').first.trim()
        : engines.first;
    final pods = _parsePods(_section(stdout, 'PODS'), engine);
    final dockerDenied = stdout.contains('---DOCKER_DENIED---');
    final dockerBody = _section(stdout, 'PS_DOCKER');
    final podmanBody = _section(stdout, 'PS_PODMAN');
    final legacy = _section(stdout, 'PS');
    final dockerRows = dockerBody.isNotEmpty
        ? parseDockerNdjson(dockerBody)
        : _legacyDocker(legacy, engine);
    final podmanRows = podmanBody.isNotEmpty
        ? parsePodmanJson(podmanBody)
        : _legacyPodman(legacy, dockerRows.isNotEmpty);
    return ContainerInventory(
      rows: [...pods, ...dockerRows, ...podmanRows],
      engines: engines,
      dockerDenied: dockerDenied,
    );
  }

  List<ContainerRow> _legacyDocker(
    String body,
    String engine,
  ) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.startsWith('[')) {
      return const [];
    }
    if (trimmed.startsWith('{') && trimmed.contains('"containers"')) {
      return _parseCrictl(
        trimmed,
        engine == 'none' || engine.isEmpty ? 'crictl' : engine,
      );
    }
    return parseDockerNdjson(trimmed);
  }

  List<ContainerRow> _legacyPodman(
    String body,
    bool alreadyGotDocker,
  ) {
    final trimmed = body.trim();
    if (!trimmed.startsWith('[')) {
      return const [];
    }
    if (alreadyGotDocker) {
      return const [];
    }
    return parsePodmanJson(trimmed);
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
