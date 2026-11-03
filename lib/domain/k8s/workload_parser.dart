import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_config.dart';

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
    displayPhase = 'Running · last $lastTerm';
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
