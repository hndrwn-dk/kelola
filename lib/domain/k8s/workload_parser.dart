import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';

WorkloadInventory parseWorkloadList(String stdout) {
  if (stdout.contains('---NO_KUBECTL---')) {
    return const WorkloadInventory(rows: [], missingKubectl: true);
  }
  final decoded = _jsonMap(stdout);
  if (decoded == null) {
    return const WorkloadInventory(rows: []);
  }
  final items = decoded['items'];
  if (items is! List) {
    final single = _item(decoded);
    return WorkloadInventory(rows: [?single]);
  }
  final rows = <K8sWorkload>[];
  for (final item in items) {
    if (item is! Map) {
      continue;
    }
    final row = _item(Map<String, dynamic>.from(item));
    if (row != null) {
      rows.add(row);
    }
  }
  return WorkloadInventory(rows: rows);
}

K8sWorkload? _item(Map<String, dynamic> raw) {
  final kind = parseK8sKind(raw['kind'] as String?);
  if (kind == null) {
    return null;
  }
  final meta = _map(raw['metadata']);
  final name = meta['name'] as String? ?? '';
  final ns = meta['namespace'] as String? ?? '';
  if (name.isEmpty) {
    return null;
  }
  final spec = _map(raw['spec']);
  final status = _map(raw['status']);
  final rollup = _rollup(kind, spec, status);
  return K8sWorkload(
    kind: kind,
    namespace: ns,
    name: name,
    ready: rollup.ready,
    desired: rollup.desired,
    phase: rollup.phase,
    health: rollup.health,
  );
}

({int ready, int desired, String phase, HealthStatus health}) _rollup(
  K8sKind kind,
  Map<String, dynamic> spec,
  Map<String, dynamic> status,
) {
  switch (kind) {
    case K8sKind.pod:
      final phase = status['phase'] as String? ?? '';
      final containers = status['containerStatuses'];
      var ready = 0;
      var desired = 0;
      if (containers is List) {
        desired = containers.length;
        for (final c in containers) {
          if (c is Map && c['ready'] == true) {
            ready++;
          }
        }
      }
      final health = switch (phase) {
        'Failed' || 'Unknown' => HealthStatus.failed,
        'Pending' => HealthStatus.warning,
        'Succeeded' => HealthStatus.healthy,
        'Running' =>
          ready == desired && desired > 0
              ? HealthStatus.healthy
              : HealthStatus.warning,
        _ => HealthStatus.unknown,
      };
      return (ready: ready, desired: desired, phase: phase, health: health);
    case K8sKind.daemonSet:
      final desired = _int(status['desiredNumberScheduled']) ?? 0;
      final ready = _int(status['numberReady']) ?? 0;
      return (
        ready: ready,
        desired: desired,
        phase: '',
        health: _ratio(ready, desired),
      );
    case K8sKind.job:
      final desired = _int(spec['completions']) ?? 1;
      final ready = _int(status['succeeded']) ?? 0;
      final failed = (_int(status['failed']) ?? 0) > 0;
      return (
        ready: ready,
        desired: desired,
        phase: '',
        health: failed
            ? HealthStatus.failed
            : _ratio(ready, desired),
      );
    case K8sKind.cronJob:
      final active = status['active'];
      final n = active is List ? active.length : 0;
      return (
        ready: n,
        desired: n,
        phase: '',
        health: HealthStatus.healthy,
      );
    case K8sKind.deployment:
    case K8sKind.statefulSet:
      final desired =
          _int(status['replicas']) ?? _int(spec['replicas']) ?? 0;
      final ready = _int(status['readyReplicas']) ?? 0;
      return (
        ready: ready,
        desired: desired,
        phase: '',
        health: _ratio(ready, desired),
      );
  }
}

HealthStatus _ratio(int ready, int desired) {
  if (desired <= 0) {
    return HealthStatus.unknown;
  }
  if (ready <= 0) {
    return HealthStatus.failed;
  }
  if (ready < desired) {
    return HealthStatus.warning;
  }
  return HealthStatus.healthy;
}

int? _int(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return int.tryParse('$v');
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

List<K8sEvent> parseEventList(String stdout) {
  final decoded = _jsonMap(stdout);
  final items = decoded?['items'];
  if (items is! List) {
    return const [];
  }
  return [
    for (final item in items)
      if (item is Map) _event(Map<String, dynamic>.from(item)),
  ];
}

K8sEvent _event(Map<String, dynamic> raw) {
  return K8sEvent(
    type: raw['type'] as String? ?? '',
    reason: raw['reason'] as String? ?? '',
    message: raw['message'] as String? ?? '',
    when: raw['lastTimestamp'] as String? ??
        raw['eventTime'] as String? ??
        '',
  );
}

List<K8sTopRow> parseTopTable(String stdout) {
  final rows = <K8sTopRow>[];
  for (final line in stdout.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 3 || parts[0].toUpperCase() == 'NAME') {
      continue;
    }
    rows.add(K8sTopRow(name: parts[0], cpu: parts[1], memory: parts[2]));
  }
  return rows;
}
