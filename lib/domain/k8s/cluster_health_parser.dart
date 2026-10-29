import 'dart:convert';

import 'package:kelola/domain/k8s/cluster_health.dart';

ClusterHealth parseClusterHealth(
  String stdout, {
  String? hostnameHint,
  bool? coreDnsReady,
}) {
  if (stdout.contains('---NO_KUBECTL---')) {
    return const ClusterHealth(
      apiReachable: false,
      controlPlaneReady: 0,
      controlPlaneDesired: 0,
      missingKubectl: true,
    );
  }

  final hostname = (_section(stdout, 'HOSTNAME') ?? hostnameHint ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .firstWhere((s) => s.isNotEmpty, orElse: () => '');

  final readyzRaw = _section(stdout, 'READYZ') ?? '';
  final apiReachable = _readyzOk(readyzRaw);

  final nodesRaw = _section(stdout, 'NODES') ?? '';
  final nodes = _parseNodes(nodesRaw);

  var cpReady = 0;
  var cpDesired = 0;
  for (final n in nodes) {
    if (!n.controlPlane) {
      continue;
    }
    cpDesired++;
    if (n.ready) {
      cpReady++;
    }
  }

  ClusterNodeMembership? thisHost;
  var matched = false;
  if (hostname.isNotEmpty) {
    for (final n in nodes) {
      if (_hostnameMatches(hostname, n.name)) {
        thisHost = n;
        matched = true;
        break;
      }
    }
  }

  return ClusterHealth(
    apiReachable: apiReachable,
    controlPlaneReady: cpReady,
    controlPlaneDesired: cpDesired,
    thisHost: thisHost,
    thisHostMatched: matched,
    coreDnsReady: coreDnsReady,
  );
}

bool _readyzOk(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.contains('---READYZ_FAIL---')) {
    return false;
  }
  final lines = t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return false;
  }
  if (lines.any((l) => l == 'ok')) {
    return true;
  }
  // verbose readyz ends with "ok" on a line; reject obvious failures
  if (t.toLowerCase().contains('error') && !lines.any((l) => l == 'ok')) {
    return false;
  }
  return lines.last == 'ok';
}

List<ClusterNodeMembership> _parseNodes(String raw) {
  final decoded = _jsonMap(raw);
  if (decoded == null) {
    return const [];
  }
  final items = decoded['items'];
  final list = <Map<String, dynamic>>[];
  if (items is List) {
    for (final item in items) {
      if (item is Map) {
        list.add(Map<String, dynamic>.from(item));
      }
    }
  } else if (decoded['kind'] == 'Node') {
    list.add(decoded);
  }
  return [for (final item in list) _node(item)];
}

ClusterNodeMembership _node(Map<String, dynamic> raw) {
  final meta = _map(raw['metadata']);
  final name = meta['name'] as String? ?? '';
  final labels = _map(meta['labels']);
  final controlPlane = labels.keys.any(
    (k) =>
        k == 'node-role.kubernetes.io/control-plane' ||
        k == 'node-role.kubernetes.io/master',
  );
  final status = _map(raw['status']);
  final conditions = status['conditions'];
  var ready = false;
  if (conditions is List) {
    for (final c in conditions) {
      if (c is Map && c['type'] == 'Ready') {
        ready = c['status'] == 'True';
        break;
      }
    }
  }
  final info = _map(status['nodeInfo']);
  return ClusterNodeMembership(
    name: name,
    ready: ready,
    kubeletVersion: info['kubeletVersion'] as String? ?? '',
    containerRuntime: info['containerRuntimeVersion'] as String? ?? '',
    controlPlane: controlPlane,
  );
}

bool _hostnameMatches(String hostname, String nodeName) {
  final h = hostname.toLowerCase();
  final n = nodeName.toLowerCase();
  if (h == n) {
    return true;
  }
  // short hostname vs FQDN either way
  if (n.startsWith('$h.') || h.startsWith('$n.')) {
    return true;
  }
  return false;
}

String? _section(String stdout, String name) {
  final startTag = '---$name---';
  final start = stdout.indexOf(startTag);
  if (start < 0) {
    return null;
  }
  var from = start + startTag.length;
  if (from < stdout.length && stdout[from] == '\n') {
    from++;
  }
  final next = RegExp(r'\n---[A-Z0-9_]+---').firstMatch(stdout.substring(from));
  if (next == null) {
    return stdout.substring(from);
  }
  return stdout.substring(from, from + next.start);
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return const {};
}

Map<String, dynamic>? _jsonMap(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw.substring(start));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } on FormatException {
    return null;
  }
  return null;
}
