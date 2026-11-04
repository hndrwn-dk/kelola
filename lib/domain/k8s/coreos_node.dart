import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';

/// M48 §4: what `CoreOsNodeProbe` read on an RHCOS / SCOS / FCOS node.
/// Node-local only; never the cluster API, never node credentials.
class CoreOsNodeStatus {
  const CoreOsNodeStatus({
    this.hostname = '',
    this.ostreeRead = false,
    this.bootedVersion = '',
    this.stagedVersion,
    this.units = const {},
    this.kubeletWarnings = const [],
    this.kubeletRead = false,
    this.runningContainers,
  });

  /// `hostname -s`, used to match this node in a bastion's cached node list.
  final String hostname;

  /// `rpm-ostree status --json` printed a deployments list.
  final bool ostreeRead;
  final String bootedVersion;

  /// Version of a staged (not yet booted) deployment; null when none.
  final String? stagedVersion;

  /// Unit → `systemctl is-active` state, for `crio` and `kubelet`.
  final Map<String, String> units;

  /// Recent kubelet warning lines, verbatim (mono).
  final List<String> kubeletWarnings;

  /// False when journal access does not allow reading, or nothing printed.
  final bool kubeletRead;

  /// Running containers from `crictl ps`; null = unknown (no sudo).
  final int? runningContainers;

  bool get updateStaged => stagedVersion != null;

  String unitState(String unit) => units[unit] ?? 'unknown';

  /// Failed when crio or kubelet is not active; warning when an update is
  /// staged or kubelet logged warnings; unknown when units were not read.
  HealthStatus get health {
    for (final u in const ['crio', 'kubelet']) {
      final s = units[u];
      if (s != null && s != 'active') {
        return HealthStatus.failed;
      }
    }
    if (units.isEmpty) {
      return HealthStatus.unknown;
    }
    if (updateStaged || kubeletWarnings.isNotEmpty) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }

  String get updateLabel {
    if (!ostreeRead) {
      return 'unknown';
    }
    if (updateStaged) {
      final v = stagedVersion!;
      return v.isEmpty
          ? 'update staged, reboot pending'
          : 'update staged ($v), reboot pending';
    }
    return 'none staged';
  }

  String get containersLabel =>
      runningContainers == null ? 'unknown' : '$runningContainers running';
}

const kCoreOsUnits = ['crio', 'kubelet'];

/// Junk-tolerant: a missing or garbled section reads as unknown.
CoreOsNodeStatus parseCoreOsNode(String stdout) {
  final hostname = (_section(stdout, 'HOSTNAME') ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .first;

  var ostreeRead = false;
  var booted = '';
  String? staged;
  final ostree = _jsonMap(_section(stdout, 'OSTREE') ?? '');
  final deployments = ostree?['deployments'];
  if (deployments is List) {
    ostreeRead = true;
    for (final d in deployments) {
      if (d is! Map) {
        continue;
      }
      final version = d['version'] is String ? d['version'] as String : '';
      if (d['booted'] == true) {
        booted = version;
      }
      if (d['staged'] == true) {
        staged = version;
      }
    }
  }

  final units = <String, String>{};
  final unitLines = [
    for (final l in (_section(stdout, 'UNITS') ?? '').split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];
  for (var i = 0; i < kCoreOsUnits.length && i < unitLines.length; i++) {
    final state = unitLines[i];
    if (RegExp(r'^[a-z-]+$').hasMatch(state)) {
      units[kCoreOsUnits[i]] = state;
    }
  }

  final kubeletRaw = _section(stdout, 'KUBELET');
  final skipped = kubeletRaw == null || kubeletRaw.contains('KELOLA_SKIP');
  final warnings = skipped
      ? const <String>[]
      : [
          for (final l in kubeletRaw.split('\n'))
            if (l.trim().isNotEmpty && !l.startsWith('-- ')) l.trimRight(),
        ];

  int? running;
  final crictl = _jsonMap(_section(stdout, 'CRICTL') ?? '');
  final containers = crictl?['containers'];
  if (containers is List) {
    running = containers.length;
  }

  return CoreOsNodeStatus(
    hostname: hostname,
    ostreeRead: ostreeRead,
    bootedVersion: booted,
    stagedVersion: staged,
    units: units,
    kubeletWarnings: warnings,
    kubeletRead: !skipped,
    runningContainers: running,
  );
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
  final end = raw.lastIndexOf('}');
  if (start < 0 || end < start) {
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
