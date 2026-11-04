import 'dart:convert';

import 'package:kelola/domain/k8s/openshift_health.dart';

/// Prefix the probe puts on the CLI's own error line when a section's read
/// printed no JSON. Not a `---MARKER---`, so section splitting ignores it.
const kOcpErrorPrefix = 'KELOLA_ERR ';

/// M48 §2a. Each section that prints no JSON becomes a per-section error,
/// never an empty list (M31 honesty rule). Junk never throws.
OpenShiftHealth parseOpenShiftHealth(String stdout) {
  final errors = <OcpSection, String>{};

  Map<String, dynamic>? read(OcpSection section, String marker) {
    final body = _section(stdout, marker);
    if (body == null) {
      errors[section] = 'no output';
      return null;
    }
    final json = _jsonMap(body);
    if (json == null) {
      errors[section] = ocpErrorReason(body);
      return null;
    }
    return json;
  }

  final cvJson = read(OcpSection.clusterVersion, 'CLUSTERVERSION');
  final coJson = read(OcpSection.clusterOperators, 'CLUSTEROPERATORS');
  final mcpJson = read(OcpSection.machineConfigPools, 'MCP');
  final csrJson = read(OcpSection.csrs, 'CSR');

  return OpenShiftHealth(
    version: cvJson == null ? null : _clusterVersion(cvJson),
    operators: coJson == null ? null : _operators(coJson),
    pools: mcpJson == null ? null : _pools(mcpJson),
    csrs: csrJson == null ? null : _csrs(csrJson),
    sectionErrors: errors,
  );
}

/// Short reason from the CLI's error text: `Forbidden`, `Unauthorized`,
/// `NotFound`, or the first line trimmed.
String ocpErrorReason(String body) {
  final lines = [
    for (final l in body.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  final errLines = [
    for (final l in lines)
      if (l.startsWith(kOcpErrorPrefix)) l.substring(kOcpErrorPrefix.length),
  ];
  final text = (errLines.isNotEmpty ? errLines : lines).join('\n');
  if (text.isEmpty) {
    return '';
  }
  if (errLines.isEmpty && text.startsWith('{')) {
    return 'unreadable output';
  }
  if (RegExp(r'\(Forbidden\)|forbidden', caseSensitive: false).hasMatch(text)) {
    return 'Forbidden';
  }
  if (text.contains('Unauthorized') ||
      text.contains('You must be logged in to the server')) {
    return 'Unauthorized';
  }
  if (text.contains("doesn't have a resource type") ||
      text.contains('(NotFound)')) {
    return 'NotFound';
  }
  final first = text.split('\n').first;
  return first.length > 120 ? '${first.substring(0, 117)}...' : first;
}

ClusterVersionState? _clusterVersion(Map<String, dynamic> raw) {
  // `get clusterversion version` returns the object; tolerate a List too.
  final obj = raw['kind'] == 'ClusterVersionList' || raw['items'] is List
      ? _firstItem(raw)
      : raw;
  if (obj == null) {
    return null;
  }
  final spec = _map(obj['spec']);
  final status = _map(obj['status']);
  final desired = _map(status['desired']);
  final conds = _conditions(status['conditions']);
  OcpCondition? cond(String type) {
    for (final c in conds) {
      if (c.type == type) {
        return c;
      }
    }
    return null;
  }

  final progressing = cond('Progressing');
  final failing = cond('Failing');
  return ClusterVersionState(
    version: _str(desired['version']),
    channel: _str(spec['channel']),
    progressing: progressing?.status == true,
    progressingMessage: progressing?.message ?? '',
    failing: failing?.status == true,
    failingMessage: failing?.message ?? '',
    availableUpdates: _list(status['availableUpdates']).length,
    overrides: _list(spec['overrides']).length,
  );
}

List<ClusterOperatorState> _operators(Map<String, dynamic> raw) {
  final out = <ClusterOperatorState>[];
  for (final item in _items(raw)) {
    final meta = _map(item['metadata']);
    final status = _map(item['status']);
    var version = '';
    for (final v in _list(status['versions'])) {
      final m = _map(v);
      if (m['name'] == 'operator') {
        version = _str(m['version']);
      }
    }
    final all = _conditions(status['conditions']);
    final kept = <OcpCondition>[
      for (final type in const ['Available', 'Progressing', 'Degraded'])
        for (final c in all)
          if (c.type == type) c,
    ];
    bool? flag(String type) {
      for (final c in kept) {
        if (c.type == type) {
          return c.status;
        }
      }
      return null;
    }

    out.add(
      ClusterOperatorState(
        name: _str(meta['name']),
        version: version,
        available: flag('Available'),
        progressing: flag('Progressing'),
        degraded: flag('Degraded'),
        conditions: kept,
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

List<MachineConfigPoolState> _pools(Map<String, dynamic> raw) {
  final out = <MachineConfigPoolState>[];
  for (final item in _items(raw)) {
    final meta = _map(item['metadata']);
    final spec = _map(item['spec']);
    final status = _map(item['status']);
    final conds = _conditions(status['conditions']);
    OcpCondition? cond(String type) {
      for (final c in conds) {
        if (c.type == type) {
          return c;
        }
      }
      return null;
    }

    final degraded = cond('Degraded');
    final updating = cond('Updating');
    final selector = _map(_map(spec['nodeSelector'])['matchLabels']);
    out.add(
      MachineConfigPoolState(
        name: _str(meta['name']),
        machineCount: _int(status['machineCount']),
        readyMachineCount: _int(status['readyMachineCount']),
        updatedMachineCount: _int(status['updatedMachineCount']),
        degradedMachineCount: _int(status['degradedMachineCount']),
        paused: spec['paused'] == true,
        degraded: degraded?.status == true,
        degradedMessage: degraded?.status == true ? degraded!.message : '',
        updating: updating?.status == true,
        updatingMessage: updating?.status == true ? updating!.message : '',
        nodeSelector: {
          for (final e in selector.entries)
            if (e.value is String) e.key: e.value as String,
        },
      ),
    );
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

PendingCsrs _csrs(Map<String, dynamic> raw) {
  final names = <String>[];
  for (final item in _items(raw)) {
    final status = _map(item['status']);
    final decided = _list(status['conditions']).any((c) {
      final t = _map(c)['type'];
      return t == 'Approved' || t == 'Denied';
    });
    if (decided) {
      continue;
    }
    names.add(_str(_map(item['spec'])['username']));
  }
  return PendingCsrs(count: names.length, usernames: names);
}

List<OcpCondition> _conditions(Object? raw) {
  return [
    for (final c in _list(raw))
      if (c is Map)
        OcpCondition(
          type: _str(c['type']),
          status: switch (c['status']) {
            'True' => true,
            'False' => false,
            _ => null,
          },
          reason: _str(c['reason']),
          message: _str(c['message']),
        ),
  ];
}

Iterable<Map<String, dynamic>> _items(Map<String, dynamic> raw) sync* {
  final items = raw['items'];
  if (items is! List) {
    return;
  }
  for (final item in items) {
    if (item is Map) {
      yield Map<String, dynamic>.from(item);
    }
  }
}

Map<String, dynamic>? _firstItem(Map<String, dynamic> raw) {
  for (final item in _items(raw)) {
    return item;
  }
  return null;
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
  final next = RegExp(r'\n?---[A-Z0-9_]+---').firstMatch(stdout.substring(from));
  if (next == null) {
    return stdout.substring(from);
  }
  return stdout.substring(from, from + next.start);
}

Map<String, dynamic>? _jsonMap(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) {
    return null;
  }
  final end = raw.lastIndexOf('}');
  if (end < start) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return const {};
}

List<Object?> _list(Object? v) => v is List ? v : const [];

String _str(Object? v) => v is String ? v : '';

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
