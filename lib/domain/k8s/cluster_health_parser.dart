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
  final authText = _section(stdout, 'AUTH') ?? '';
  final authExpired = authExpiredFromText(authText);
  // An expired login is an answer from the API, never "API down".
  final apiReachable = authExpired || _readyzOk(readyzRaw);

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
    kubeconfigDenied: !apiReachable && kubeconfigDeniedFromText(authText),
    controlPlaneReady: cpReady,
    controlPlaneDesired: cpDesired,
    thisHost: thisHost,
    thisHostMatched: matched,
    coreDnsReady: coreDnsReady,
    nodes: nodes,
    // The OpenShift section fails for the same auth reason, so an expired
    // login says nothing about the cluster kind.
    isOpenShift: authExpired ? null : parseIsOpenShift(stdout),
    authExpired: authExpired,
    kubeContext: parseKubeContext(stdout),
  );
}

/// M48 §1b. `true` when the API discovery doc for `config.openshift.io/v1`
/// came back; `false` on `---OPENSHIFT_NONE---`, a 404, or an empty body;
/// `null` when the section is missing or holds junk.
bool? parseIsOpenShift(String stdout) {
  if (!stdout.contains('---OPENSHIFT---')) {
    return null;
  }
  if (stdout.contains('---OPENSHIFT_NONE---')) {
    return false;
  }
  final body = (_section(stdout, 'OPENSHIFT') ?? '').trim();
  if (body.isEmpty) {
    return false;
  }
  if (RegExp(r'\b404\b|NotFound|not found', caseSensitive: false)
      .hasMatch(body)) {
    return false;
  }
  final json = _jsonMap(body);
  if (json == null) {
    return null;
  }
  return json['groupVersion'] == 'config.openshift.io/v1';
}

/// First line of `---CONTEXT---`; empty when missing or not a context name
/// (CLI errors have spaces; context names do not).
String parseKubeContext(String stdout) {
  final body = _section(stdout, 'CONTEXT');
  if (body == null) {
    return '';
  }
  final line = body
      .split('\n')
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty || line.contains(RegExp(r'\s')) || line.startsWith('---')) {
    return '';
  }
  return line;
}

/// M48 §1d. Strings `oc` / `kubectl` print when the login is no longer valid.
const kAuthExpiredMarkers = [
  'Unauthorized',
  'You must be logged in to the server',
  'the server has asked for the client to provide credentials',
];

bool authExpiredFromText(String text) {
  if (text.trim().isEmpty) {
    return false;
  }
  return kAuthExpiredMarkers.any(text.contains);
}

/// The CLI could not open its kubeconfig, e.g. k3s `k3s.yaml` is root-only.
bool kubeconfigDeniedFromText(String text) {
  return RegExp(
    r'Unable to read \S*k3s\.yaml|error loading config file.*permission denied',
    caseSensitive: false,
  ).hasMatch(text);
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
  final annotations = _map(meta['annotations']);
  final controlPlane = labels.keys.any(
    (k) =>
        k == 'node-role.kubernetes.io/control-plane' ||
        k == 'node-role.kubernetes.io/master',
  );
  final status = _map(raw['status']);
  final conditions = status['conditions'];
  var ready = false;
  final pressures = <String>[];
  if (conditions is List) {
    for (final c in conditions) {
      if (c is! Map) {
        continue;
      }
      final type = c['type'] as String? ?? '';
      if (type == 'Ready') {
        ready = c['status'] == 'True';
      } else if (type.isNotEmpty && c['status'] == 'True') {
        pressures.add(type);
      }
    }
  }
  final info = _map(status['nodeInfo']);
  final current = _str(annotations['$_mcPrefix/currentConfig']);
  final desired = _str(annotations['$_mcPrefix/desiredConfig']);
  return ClusterNodeMembership(
    name: name,
    ready: ready,
    kubeletVersion: _str(info['kubeletVersion']),
    containerRuntime: _str(info['containerRuntimeVersion']),
    osImage: _str(info['osImage']),
    controlPlane: controlPlane,
    pressures: pressures,
    mcdState: _mcdState(_str(annotations['$_mcPrefix/state'])),
    updatePending:
        current.isNotEmpty && desired.isNotEmpty && current != desired,
    mcdReason: _str(annotations['$_mcPrefix/reason']),
    roles: [
      for (final role in _kRoles)
        if (labels.containsKey('node-role.kubernetes.io/$role')) role,
    ],
    labels: {
      for (final e in labels.entries)
        if (e.value is String) e.key: e.value as String,
    },
  );
}

const _mcPrefix = 'machineconfiguration.openshift.io';
const _kRoles = ['master', 'control-plane', 'worker', 'infra'];

McdState? _mcdState(String raw) {
  return switch (raw) {
    'Done' => McdState.done,
    'Working' => McdState.working,
    'Degraded' || 'Unreconcilable' => McdState.degraded,
    _ => null,
  };
}

String _str(Object? v) => v is String ? v : '';

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
  // Newline optional: `kubectl get --raw` output has none, so the next
  // marker can follow the body on the same line.
  final next = RegExp(r'\n?---[A-Z0-9_]+---').firstMatch(stdout.substring(from));
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
