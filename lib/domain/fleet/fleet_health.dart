import 'package:kelola/domain/hosts/host.dart';

enum FleetSeverity {
  unreachable,
  failedUnits,
  diskHigh,
  pendingUpdates,
  loadHigh,
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
    this.fromCache = false,
  });

  final String hostId;
  final String alias;
  final bool reachable;
  final double load1;
  final int diskRootPercent;
  final int failedUnitCount;
  final int pendingUpdates;
  final DateTime fetchedAt;
  final bool fromCache;

  static const loadHighThreshold = 4.0;
  static const diskHighThreshold = 90;

  FleetSeverity get severity {
    if (!reachable) {
      return FleetSeverity.unreachable;
    }
    if (failedUnitCount > 0) {
      return FleetSeverity.failedUnits;
    }
    if (diskRootPercent >= diskHighThreshold) {
      return FleetSeverity.diskHigh;
    }
    if (pendingUpdates > 0) {
      return FleetSeverity.pendingUpdates;
    }
    if (load1 >= loadHighThreshold) {
      return FleetSeverity.loadHigh;
    }
    return FleetSeverity.healthy;
  }

  bool isStale({DateTime? now}) {
    final n = (now ?? DateTime.now()).toUtc();
    return n.difference(fetchedAt.toUtc()) > Host.attentionFreshFor;
  }

  String ageLabel({DateTime? now}) => Host.ageLabel(fetchedAt, now: now);

  String metaLine({DateTime? now}) {
    if (!reachable) {
      final age = ageLabel(now: now);
      return fromCache || fetchedAt.millisecondsSinceEpoch > 0
          ? 'unreachable · cache $age'
          : 'unreachable';
    }
    final bits = <String>[
      'load ${load1.toStringAsFixed(2)}',
      'disk $diskRootPercent%',
      '$failedUnitCount failed',
      '$pendingUpdates updates',
    ];
    if (fromCache || isStale(now: now)) {
      bits.add('cache ${ageLabel(now: now)}');
    }
    return bits.join(' · ');
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
