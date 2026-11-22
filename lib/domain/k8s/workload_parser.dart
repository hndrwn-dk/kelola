import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/custom_columns.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_config.dart';

/// Whether [stdout] is a [kWorkloadReaderColumns] table.
bool isWorkloadReaderTable(String stdout) =>
    hasCustomColumnsHeader(stdout, kWorkloadReaderColumns);

/// One [kWorkloadReaderColumns] row as the JSON shape [_item] reads. The
/// parser only counts containers and takes the first reason, so a reason
/// may sit on any container.
Map<String, dynamic> _rowAsJson(Map<String, String> r) {
  List<String> list(String k) =>
      r[k]!.isEmpty ? const [] : r[k]!.split(',');
  int? n(String k) => int.tryParse(r[k]!);
  List<Map<String, dynamic>> statuses({
    required List<String> counts,
    List<String> ready = const [],
    List<String> waiting = const [],
    List<String> terminated = const [],
  }) {
    final len = [
      counts.length,
      ready.length,
      waiting.length,
      terminated.length,
    ].reduce((a, b) => a > b ? a : b);
    return [
      for (var i = 0; i < len; i++)
        {
          if (i < ready.length) 'ready': ready[i] == 'true',
          if (i < counts.length) 'restartCount': int.tryParse(counts[i]) ?? 0,
          if (i < waiting.length)
            'state': {
              'waiting': {'reason': waiting[i]},
            },
          if (i < terminated.length)
            'lastState': {
              'terminated': {'reason': terminated[i]},
            },
        },
    ];
  }

  return {
    'kind': r['A'],
    'metadata': {'namespace': r['B'], 'name': r['C']},
    'spec': {'replicas': n('D'), 'completions': n('I')}
      ..removeWhere((_, v) => v == null),
    'status': <String, dynamic>{
      'replicas': n('E'),
      'readyReplicas': n('F'),
      'desiredNumberScheduled': n('G'),
      'numberReady': n('H'),
      'succeeded': n('J'),
      'failed': n('K'),
      if (r['L']!.isNotEmpty) 'active': list('L'),
      if (r['M']!.isNotEmpty) 'phase': r['M'],
      'containerStatuses': statuses(
        counts: list('O'),
        ready: list('N'),
        waiting: list('P'),
        terminated: list('Q'),
      ),
      'initContainerStatuses': statuses(
        counts: list('R'),
        waiting: list('S'),
      ),
    }..removeWhere((_, v) => v == null),
  };
}

WorkloadInventory parseWorkloadList(String stdout) {
  if (stdout.contains('---NO_KUBECTL---')) {
    return const WorkloadInventory(rows: [], missingKubectl: true);
  }
  if (isWorkloadReaderTable(stdout)) {
    return WorkloadInventory(
      rows: [
        for (final r in parseCustomColumns(stdout, kWorkloadReaderColumns))
          ?_item(_rowAsJson(r)),
      ],
    );
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
    restarts: kind == K8sKind.pod ? _podRestarts(status) : 0,
    podPhase: kind == K8sKind.pod ? status['phase'] as String? ?? '' : '',
    config: _podConfig(kind, meta, spec),
  );
}

K8sPodConfig? _podConfig(
  K8sKind kind,
  Map<String, dynamic> meta,
  Map<String, dynamic> spec,
) {
  final Map<String, dynamic> podSpec = switch (kind) {
    K8sKind.pod => spec,
    K8sKind.cronJob => _map(
        _map(_map(_map(spec['jobTemplate'])['spec'])['template'])['spec'],
      ),
    _ => _map(_map(spec['template'])['spec']),
  };
  if (podSpec.isEmpty) {
    return null;
  }
  final owners = meta['ownerReferences'];
  return parsePodSpec(
    podSpec,
    ownedByController: owners is List && owners.isNotEmpty,
  );
}

/// Waiting reasons that will not fix themselves without a change.
const _failedWaiting = {
  'CrashLoopBackOff',
  'ImagePullBackOff',
  'ErrImagePull',
  'InvalidImageName',
  'CreateContainerConfigError',
  'CreateContainerError',
  'RunContainerError',
};

({String reason, bool init}) _waitingReason(Map<String, dynamic> status) {
  for (final key in ['initContainerStatuses', 'containerStatuses']) {
    final list = status[key];
    if (list is! List) {
      continue;
    }
    for (final c in list) {
      if (c is! Map) {
        continue;
      }
      final waiting = _map(_map(c['state'])['waiting']);
      final reason = waiting['reason'] as String? ?? '';
      // PodInitializing is the normal wait while init containers run.
      if (reason.isNotEmpty && reason != 'PodInitializing') {
        return (reason: reason, init: key == 'initContainerStatuses');
      }
    }
  }
  return (reason: '', init: false);
}

int _podRestarts(Map<String, dynamic> status) {
  var total = 0;
  for (final key in ['initContainerStatuses', 'containerStatuses']) {
    final list = status[key];
    if (list is! List) {
      continue;
    }
    for (final c in list) {
      if (c is Map) {
        total += _int(c['restartCount']) ?? 0;
      }
    }
  }
  return total;
}

/// `OOMKilled` / `Error` from the last terminated container, if any.
String _lastTerminatedReason(Map<String, dynamic> status) {
  final list = status['containerStatuses'];
  if (list is! List) {
    return '';
  }
  for (final c in list) {
    if (c is! Map) {
      continue;
    }
    final term = _map(_map(c['lastState'])['terminated']);
    final reason = term['reason'] as String? ?? '';
    if (reason.isNotEmpty) {
      return reason;
    }
  }
  return '';
}

({int ready, int desired, String phase, HealthStatus health}) _podRollup(
  Map<String, dynamic> status,
) {
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
  final waiting = _waitingReason(status);
  final restarts = _podRestarts(status);
  final lastTerm = _lastTerminatedReason(status);

  var displayPhase = phase;
  if (waiting.reason.isNotEmpty) {
    displayPhase = waiting.init ? 'Init:${waiting.reason}' : waiting.reason;
  } else if (phase == 'Pending') {
    // Unschedulable / Insufficient cpu reads better than bare Pending.
    final conditions = status['conditions'];
    if (conditions is List) {
      for (final c in conditions) {
        if (c is Map &&
            c['type'] == 'PodScheduled' &&
            c['status'] == 'False' &&
            (c['reason'] as String? ?? '').isNotEmpty) {
          displayPhase = 'Pending · ${c['reason']}';
          break;
        }
      }
    }
  }

  final HealthStatus health;
  if (_failedWaiting.contains(waiting.reason) ||
      phase == 'Failed' ||
      phase == 'Unknown') {
    health = HealthStatus.failed;
  } else {
    health = switch (phase) {
      'Pending' => HealthStatus.warning,
      'Succeeded' => HealthStatus.healthy,
      'Running' => ready == desired && desired > 0 && restarts < kRestartWarn
          ? HealthStatus.healthy
          : HealthStatus.warning,
      _ => HealthStatus.unknown,
    };
  }
  if (health != HealthStatus.healthy &&
      waiting.reason.isEmpty &&
      phase == 'Running' &&
      lastTerm.isNotEmpty &&
      restarts > 0) {
    // kubelet reports reason `Unknown` when it lost the container's exit
    // (typically a node or kubelet restart). "last Unknown" reads like a
    // bug; say what it means.
    displayPhase = lastTerm == 'Unknown'
        ? 'Running · last exit unknown'
        : 'Running · last $lastTerm';
  }
  return (
    ready: ready,
    desired: desired,
    phase: displayPhase,
    health: health,
  );
}

({int ready, int desired, String phase, HealthStatus health}) _rollup(
  K8sKind kind,
  Map<String, dynamic> spec,
  Map<String, dynamic> status,
) {
  switch (kind) {
    case K8sKind.pod:
      return _podRollup(status);
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
      // spec.replicas is what the owner asked for; status.replicas can sit
      // above it mid-rollout (surge) and hide a short count.
      final desired =
          _int(spec['replicas']) ?? _int(status['replicas']) ?? 0;
      final ready = _int(status['readyReplicas']) ?? 0;
      if (desired == 0) {
        return (
          ready: ready,
          desired: 0,
          phase: 'scaled to 0',
          health: HealthStatus.healthy,
        );
      }
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
