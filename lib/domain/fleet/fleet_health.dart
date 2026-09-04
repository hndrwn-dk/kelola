import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/risk/risk_level.dart';

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
  securityUpdates,
  pendingUpdates,
  loadHigh,
  memHigh,
  rebootRequired,
  healthy,
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

  FleetSeverity get severity {
    if (!reachable) {
      return FleetSeverity.unreachable;
    }
    if (failedUnitCount > 0) {
      return FleetSeverity.failedUnits;
    }
    if (containerTroubleCount > 0) {
      return FleetSeverity.badContainers;
    }
    if (diskRootPercent >= diskHighThreshold || highDiskMounts.isNotEmpty) {
      return FleetSeverity.diskHigh;
    }
    if (securityUpdates > 0) {
      return FleetSeverity.securityUpdates;
    }
    if (pendingUpdates > 0) {
      return FleetSeverity.pendingUpdates;
    }
    final ratio = loadRatio;
    if (ratio != null) {
      if (ratio >= loadRatioHigh) {
        return FleetSeverity.loadHigh;
      }
    } else if (load1 >= loadHighFallback) {
      return FleetSeverity.loadHigh;
    }
    if (memPercent >= memHighThreshold) {
      return FleetSeverity.memHigh;
    }
    if (rebootRequired) {
      return FleetSeverity.rebootRequired;
    }
    return FleetSeverity.healthy;
  }

  /// Band risk for [FleetHostTile]. Load ≥100% is destructive (red).
  RiskLevel get tileRiskLevel {
    switch (severity) {
      case FleetSeverity.unreachable:
      case FleetSeverity.loadHigh:
        return RiskLevel.destructive;
      case FleetSeverity.failedUnits:
      case FleetSeverity.badContainers:
      case FleetSeverity.diskHigh:
        return RiskLevel.mutate;
      case FleetSeverity.securityUpdates:
      case FleetSeverity.pendingUpdates:
      case FleetSeverity.memHigh:
      case FleetSeverity.rebootRequired:
      case FleetSeverity.healthy:
        return RiskLevel.read;
    }
  }

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
    final ratio = loadRatio;
    final loadVal = ratio == null
        ? load1.toStringAsFixed(2)
        : '${(ratio * 100).round()}%';
    final cells = <FleetTileMetric>[
      FleetTileMetric(label: 'load', value: loadVal),
      FleetTileMetric(label: 'mem', value: '$memPercent%'),
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
    if (!reachable) {
      return fromCache || fetchedAt.millisecondsSinceEpoch > 0
          ? 'down · cache ${ageLabel(now: now)}'
          : 'unreachable';
    }
    return tileMetrics(now: now)
        .map((m) => '${m.label} ${m.value}')
        .join(' · ');
  }
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
