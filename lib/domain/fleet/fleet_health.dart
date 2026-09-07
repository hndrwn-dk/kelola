import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';

class FleetTileMetric {
  const FleetTileMetric({required this.label, required this.value});

  final String label;
  final String value;
}

enum FleetSeverity {
  unreachable,
  failedUnits,
  badContainers,
  diskHigh,
  loadHigh,
  memHigh,
  securityUpdates,
  pendingUpdates,
  rebootRequired,
  healthy,
}

/// Host condition for fleet tiles — not action risk ([RiskLevel]).
enum FleetTileHealth {
  healthy,
  warning,
  failed,
  unknown,
}

enum FleetIssueKind {
  unreachable,
  failedUnit,
  badContainer,
  diskCritical,
  loadHigh,
  memHigh,
  securityUpdates,
  pendingUpdates,
  rebootRequired,
}

class FleetIssue {
  const FleetIssue({
    required this.kind,
    required this.label,
    required this.meta,
  });

  final FleetIssueKind kind;
  final String label;
  final String meta;

  bool get isActionable =>
      kind == FleetIssueKind.failedUnit ||
      kind == FleetIssueKind.badContainer ||
      kind == FleetIssueKind.diskCritical ||
      kind == FleetIssueKind.securityUpdates;
}

class FleetAssessment {
  const FleetAssessment({
    required this.severity,
    required this.tileHealth,
    required this.issues,
  });

  final FleetSeverity severity;
  final FleetTileHealth tileHealth;
  final List<FleetIssue> issues;

  bool get isHealthy => severity == FleetSeverity.healthy;
}

class FleetHostHealth {
  const FleetHostHealth({
    required this.hostId,
    required this.alias,
    required this.reachable,
    required this.load1,
    required this.diskRootPercent,
    required this.failedUnitCount,
    required this.pendingUpdates,
    required this.fetchedAt,
    this.nprocCores,
    this.memPercent = 0,
    this.highDiskMounts = const [],
    this.securityUpdates = 0,
    this.containersDown = 0,
    this.containersUnhealthy = 0,
    this.uptime = Duration.zero,
    this.rebootRequired = false,
    this.fromCache = false,
    this.outcome = HostProbeOutcome.pending,
  });

  final String hostId;
  final String alias;
  final bool reachable;
  final double load1;
  final int? nprocCores;
  final int memPercent;
  final int diskRootPercent;
  final List<String> highDiskMounts;
  final int failedUnitCount;
  final int pendingUpdates;
  final int securityUpdates;
  final int containersDown;
  final int containersUnhealthy;
  final Duration uptime;
  final bool rebootRequired;
  final DateTime fetchedAt;
  final bool fromCache;
  final HostProbeOutcome outcome;

  static const loadRatioHigh = 1.0;
  static const loadHighFallback = 4.0;
  static const diskHighThreshold = 90;
  static const diskWarnMount = 85;
  static const memHighThreshold = 90;

  double? get loadRatio {
    final n = nprocCores;
    if (n == null || n <= 0) {
      return null;
    }
    return load1 / n;
  }

  int get containerTroubleCount => containersDown + containersUnhealthy;

  String get containersLabel {
    if (containerTroubleCount == 0) {
      return '0';
    }
    return '$containersDown down / $containersUnhealthy unhealthy';
  }

  /// Single source for severity, tile health, and ISSUES.
  ///
  /// Priority: unreachable → failed units → bad containers → disk → load →
  /// mem → security → pending → reboot. Unreachable blocks ops; broken
  /// workloads next; then resource pressure; package debt last.
  FleetSeverity get severity => assessFleetHost(this).severity;

  FleetTileHealth get tileHealth => assessFleetHost(this).tileHealth;

  bool isStale({DateTime? now}) {
    final n = (now ?? DateTime.now()).toUtc();
    return n.difference(fetchedAt.toUtc()) > Host.attentionFreshFor;
  }

  String ageLabel({DateTime? now}) => Host.ageLabel(fetchedAt, now: now);

  String uptimeLabel() {
    final d = uptime;
    if (d.inDays >= 1) {
      return '${d.inDays}d';
    }
    if (d.inHours >= 1) {
      return '${d.inHours}h';
    }
    return '${d.inMinutes}m';
  }

  /// Compact metric cells for the fleet tile. Zero trouble fields omitted.
  List<FleetTileMetric> tileMetrics({DateTime? now}) {
    if (!reachable) {
      return const [];
    }
    final live = fleetLiveStrings(this, now: now);
    final cells = <FleetTileMetric>[
      FleetTileMetric(label: 'load', value: live.load),
      FleetTileMetric(label: 'mem', value: live.mem),
      FleetTileMetric(label: 'disk', value: '$diskRootPercent%'),
      FleetTileMetric(label: 'up', value: uptimeLabel()),
    ];
    if (failedUnitCount > 0) {
      cells.add(FleetTileMetric(label: 'fail', value: '$failedUnitCount'));
    }
    if (containerTroubleCount > 0) {
      cells.add(
        FleetTileMetric(label: 'ctr', value: '$containerTroubleCount'),
      );
    }
    if (securityUpdates > 0) {
      cells.add(FleetTileMetric(label: 'sec', value: '$securityUpdates'));
    } else if (pendingUpdates > 0) {
      cells.add(FleetTileMetric(label: 'upd', value: '$pendingUpdates'));
    }
    if (rebootRequired) {
      cells.add(const FleetTileMetric(label: 'reboot', value: 'yes'));
    }
    if (fromCache || isStale(now: now)) {
      cells.add(FleetTileMetric(label: 'cache', value: ageLabel(now: now)));
    }
    return cells;
  }

  String tileSummary({DateTime? now}) {
    if (outcome != HostProbeOutcome.healthy && !reachable) {
      return fleetUnreachableMessage(
        outcome: outcome == HostProbeOutcome.pending
            ? HostProbeOutcome.unreachable
            : outcome,
        hasCache: fromCache || fetchedAt.millisecondsSinceEpoch > 0,
        fetchedAt: fetchedAt,
        now: now,
      );
    }
    if (!reachable) {
      return fleetUnreachableMessage(
        outcome: HostProbeOutcome.unreachable,
        hasCache: fromCache || fetchedAt.millisecondsSinceEpoch > 0,
        fetchedAt: fetchedAt,
        now: now,
      );
    }
    return tileMetrics(now: now)
        .map((m) => '${m.label} ${m.value}')
        .join(' · ');
  }

  FleetHostHealth copyWith({
    double? load1,
    int? nprocCores,
    int? memPercent,
    DateTime? fetchedAt,
    bool? fromCache,
    bool? reachable,
    HostProbeOutcome? outcome,
  }) {
    return FleetHostHealth(
      hostId: hostId,
      alias: alias,
      reachable: reachable ?? this.reachable,
      load1: load1 ?? this.load1,
      nprocCores: nprocCores ?? this.nprocCores,
      memPercent: memPercent ?? this.memPercent,
      diskRootPercent: diskRootPercent,
      highDiskMounts: highDiskMounts,
      failedUnitCount: failedUnitCount,
      pendingUpdates: pendingUpdates,
      securityUpdates: securityUpdates,
      containersDown: containersDown,
      containersUnhealthy: containersUnhealthy,
      uptime: uptime,
      rebootRequired: rebootRequired,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      fromCache: fromCache ?? this.fromCache,
      outcome: outcome ?? this.outcome,
    );
  }
}

/// Load as core-normalized percent when [nprocCores] is known; else raw loadavg.
String formatFleetLoad(double load1, int? nprocCores) {
  if (nprocCores == null || nprocCores <= 0) {
    return load1.toStringAsFixed(2);
  }
  return '${((load1 / nprocCores) * 100).round()}%';
}

class FleetLiveStrings {
  const FleetLiveStrings({
    required this.load,
    required this.mem,
    required this.age,
  });

  final String load;
  final String mem;
  final String age;
}

/// Merge a metrics sample into the fleet row (preserves [nprocCores]).
FleetHostHealth applyFleetMetricsSample(
  FleetHostHealth prior, {
  required double load1,
  required int memPercent,
  DateTime? now,
}) {
  return prior.copyWith(
    load1: load1,
    memPercent: memPercent,
    fetchedAt: (now ?? DateTime.now()).toUtc(),
    fromCache: false,
    reachable: true,
  );
}

/// Sheet LIVE + tile cells must both use this for the same [FleetHostHealth].
FleetLiveStrings fleetLiveStrings(FleetHostHealth health, {DateTime? now}) {
  return FleetLiveStrings(
    load: formatFleetLoad(health.load1, health.nprocCores),
    mem: '${health.memPercent}%',
    age: health.ageLabel(now: now),
  );
}

/// Map live fleet probe into Host inventory attention buckets.
HostAttention attentionFromFleetHealth(FleetHostHealth health) {
  if (!health.reachable) {
    return HostAttention.unreachable;
  }
  if (health.failedUnitCount > 0) {
    return HostAttention.failedUnits;
  }
  if (health.diskRootPercent >= FleetHostHealth.diskHighThreshold ||
      health.highDiskMounts.isNotEmpty) {
    return HostAttention.diskHigh;
  }
  return HostAttention.healthy;
}

/// One verdict for tile + sheet. Issues cover every non-healthy severity.
FleetAssessment assessFleetHost(FleetHostHealth health) {
  final issues = <FleetIssue>[];

  if (!health.reachable) {
    issues.add(
      const FleetIssue(
        kind: FleetIssueKind.unreachable,
        label: 'Host unreachable',
        meta: 'SSH failed',
      ),
    );
  }
  if (health.reachable && health.failedUnitCount > 0) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.failedUnit,
        label: 'Restart failed unit',
        meta: '${health.failedUnitCount} failed',
      ),
    );
  }
  if (health.reachable && health.containerTroubleCount > 0) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.badContainer,
        label: 'Inspect containers',
        meta: health.containersLabel,
      ),
    );
  }
  if (health.reachable &&
      (health.diskRootPercent >= FleetHostHealth.diskHighThreshold ||
          health.highDiskMounts.isNotEmpty)) {
    final mounts = [
      if (health.diskRootPercent >= FleetHostHealth.diskHighThreshold)
        '/:${health.diskRootPercent}%',
      ...health.highDiskMounts,
    ].join(' · ');
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.diskCritical,
        label: 'Review disk',
        meta: mounts,
      ),
    );
  }

  if (health.reachable && _isLoadHigh(health)) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.loadHigh,
        label: 'Load high',
        meta: formatFleetLoad(health.load1, health.nprocCores),
      ),
    );
  }
  if (health.reachable &&
      health.memPercent >= FleetHostHealth.memHighThreshold) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.memHigh,
        label: 'Memory high',
        meta: '${health.memPercent}%',
      ),
    );
  }
  if (health.reachable && health.securityUpdates > 0) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.securityUpdates,
        label: 'Security updates',
        meta: '${health.securityUpdates} security',
      ),
    );
  }
  if (health.reachable && health.pendingUpdates > 0) {
    issues.add(
      FleetIssue(
        kind: FleetIssueKind.pendingUpdates,
        label: 'Pending updates',
        meta: '${health.pendingUpdates} pending',
      ),
    );
  }
  if (health.reachable && health.rebootRequired) {
    issues.add(
      const FleetIssue(
        kind: FleetIssueKind.rebootRequired,
        label: 'Reboot required',
        meta: 'pending',
      ),
    );
  }

  final severity = _severityFromIssues(issues);
  return FleetAssessment(
    severity: severity,
    tileHealth: _tileHealth(severity),
    issues: List.unmodifiable(issues),
  );
}

bool _isLoadHigh(FleetHostHealth health) {
  final ratio = health.loadRatio;
  if (ratio != null) {
    return ratio >= FleetHostHealth.loadRatioHigh;
  }
  return health.load1 >= FleetHostHealth.loadHighFallback;
}

FleetSeverity _severityFromIssues(List<FleetIssue> issues) {
  if (issues.isEmpty) {
    return FleetSeverity.healthy;
  }
  return switch (issues.first.kind) {
    FleetIssueKind.unreachable => FleetSeverity.unreachable,
    FleetIssueKind.failedUnit => FleetSeverity.failedUnits,
    FleetIssueKind.badContainer => FleetSeverity.badContainers,
    FleetIssueKind.diskCritical => FleetSeverity.diskHigh,
    FleetIssueKind.loadHigh => FleetSeverity.loadHigh,
    FleetIssueKind.memHigh => FleetSeverity.memHigh,
    FleetIssueKind.securityUpdates => FleetSeverity.securityUpdates,
    FleetIssueKind.pendingUpdates => FleetSeverity.pendingUpdates,
    FleetIssueKind.rebootRequired => FleetSeverity.rebootRequired,
  };
}

FleetTileHealth _tileHealth(FleetSeverity severity) {
  return switch (severity) {
    FleetSeverity.unreachable => FleetTileHealth.unknown,
    FleetSeverity.failedUnits ||
    FleetSeverity.badContainers ||
    FleetSeverity.loadHigh =>
      FleetTileHealth.failed,
    FleetSeverity.diskHigh ||
    FleetSeverity.memHigh ||
    FleetSeverity.securityUpdates ||
    FleetSeverity.pendingUpdates ||
    FleetSeverity.rebootRequired =>
      FleetTileHealth.warning,
    FleetSeverity.healthy => FleetTileHealth.healthy,
  };
}

List<FleetHostHealth> sortFleetHealth(Iterable<FleetHostHealth> rows) {
  final list = List<FleetHostHealth>.of(rows);
  list.sort((a, b) {
    final bySev = a.severity.index.compareTo(b.severity.index);
    if (bySev != 0) {
      return bySev;
    }
    return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
  });
  return list;
}

List<FleetHostHealth> filterFleetByTag(
  Iterable<FleetHostHealth> rows,
  Map<String, List<String>> tagsByHostId,
  String? tag,
) {
  if (tag == null || tag.isEmpty) {
    return List<FleetHostHealth>.of(rows);
  }
  return [
    for (final r in rows)
      if ((tagsByHostId[r.hostId] ?? const []).contains(tag)) r,
  ];
}

/// Count restarting / unhealthy / exited(non-zero). Exit 0 is ignored.
({int down, int unhealthy}) countFleetContainerTrouble(Iterable<String> lines) {
  var down = 0;
  var unhealthy = 0;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    final parts = line.split('\t');
    final state = (parts.isNotEmpty ? parts[0] : '').toLowerCase();
    final status = (parts.length > 1 ? parts[1] : '').toLowerCase();
    if (status.contains('unhealthy')) {
      unhealthy++;
    }
    if (state == 'restarting') {
      down++;
      continue;
    }
    if (state == 'exited' || state == 'dead') {
      final m = RegExp(r'exited\s*\((\-?\d+)\)').firstMatch(status);
      final code = int.tryParse(m?.group(1) ?? '');
      if (code != null && code != 0) {
        down++;
      }
    }
  }
  return (down: down, unhealthy: unhealthy);
}
