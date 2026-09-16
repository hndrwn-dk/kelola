import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';

enum HostInventoryBucket { needsAttention, healthy, notChecked }

class HostInventoryView {
  const HostInventoryView({
    required this.needsAttention,
    required this.healthy,
    required this.notChecked,
  });

  final List<Host> needsAttention;
  final List<Host> healthy;
  final List<Host> notChecked;

  int get total =>
      needsAttention.length + healthy.length + notChecked.length;

  /// Compact header: `2 · 1 needs attention` — no healthy echo, no "hosts".
  String get summary {
    final parts = <String>['$total'];
    if (needsAttention.isNotEmpty) {
      parts.add('${needsAttention.length} needs attention');
    }
    if (notChecked.isNotEmpty) {
      parts.add('${notChecked.length} not checked');
    }
    return parts.join(' · ');
  }

  static HostInventoryView build(List<Host> hosts, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final needs = <Host>[];
    final ok = <Host>[];
    final unchecked = <Host>[];
    for (final host in hosts) {
      switch (inventoryBucket(host, now: clock)) {
        case HostInventoryBucket.needsAttention:
          needs.add(host);
        case HostInventoryBucket.healthy:
          ok.add(host);
        case HostInventoryBucket.notChecked:
          unchecked.add(host);
      }
    }
    int byRankThenAlias(Host a, Host b) {
      final r = attentionRank(a).compareTo(attentionRank(b));
      if (r != 0) {
        return r;
      }
      return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
    }
    needs.sort(byRankThenAlias);
    ok.sort(byRankThenAlias);
    unchecked.sort(byRankThenAlias);
    return HostInventoryView(
      needsAttention: needs,
      healthy: ok,
      notChecked: unchecked,
    );
  }
}

const inventoryCollapseAfter = 8;

bool collapseInventoryGroup(HostInventoryBucket bucket, int count) {
  if (bucket == HostInventoryBucket.needsAttention) {
    return false;
  }
  return count > inventoryCollapseAfter;
}

String collapsedInventoryLabel(HostInventoryBucket bucket, int count) {
  final name = switch (bucket) {
    HostInventoryBucket.needsAttention => 'NEEDS ATTENTION',
    HostInventoryBucket.healthy => 'HEALTHY',
    HostInventoryBucket.notChecked => 'NOT CHECKED',
  };
  return '$name · $count';
}

String inventoryGroupLabel(HostInventoryBucket bucket) {
  return switch (bucket) {
    HostInventoryBucket.needsAttention => 'Needs attention',
    HostInventoryBucket.healthy => 'Healthy',
    HostInventoryBucket.notChecked => 'Not checked',
  };
}

HostInventoryBucket inventoryBucket(Host host, {DateTime? now}) {
  if (host.attentionAt == null) {
    if (host.attention == HostAttention.unreachable) {
      return HostInventoryBucket.needsAttention;
    }
    return HostInventoryBucket.notChecked;
  }
  if (host.isAttentionStale(now: now)) {
    return HostInventoryBucket.notChecked;
  }
  if (host.needsAttention) {
    return HostInventoryBucket.needsAttention;
  }
  if (host.attention == HostAttention.healthy) {
    return HostInventoryBucket.healthy;
  }
  return HostInventoryBucket.notChecked;
}

/// Hosts row trailing metrics from fleet cache: load · mem · disk.
///
/// Whole line is null when unmonitored, unreachable, or cache missing —
/// never invent live-looking zeros. Known values are emitted per-field;
/// unknown disk is omitted (Rocky partial reads keep load/mem).
///
/// Load uses an `L` prefix so it is not confused with dashboard CPU %
/// from `/proc/stat`.
String? hostInventoryMetricsLine({
  required Host host,
  required bool monitored,
  required FleetHostHealth? cache,
}) {
  if (!monitored) {
    return null;
  }
  if (host.attention == HostAttention.unreachable) {
    return null;
  }
  if (cache == null || !cache.reachable) {
    return null;
  }
  final parts = <String>[];
  parts.add('L${formatFleetLoad(cache.load1, cache.nprocCores)}');
  parts.add('${cache.memPercent}%');
  final disk = cache.diskRootPercent;
  if (disk != null) {
    parts.add('$disk%');
  }
  return parts.join(' · ');
}

/// Legacy hook — inventory no longer shows disk%/age detail under the row.
String? hostInventoryDetail(Host host, {DateTime? now}) => null;
