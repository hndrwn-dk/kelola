import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';

class HomeWidgetSnapshot {
  const HomeWidgetSnapshot({
    required this.enabled,
    this.hostId,
    this.alias,
    this.failedCount = 0,
    this.refreshedAt,
  });

  final bool enabled;
  final String? hostId;
  final String? alias;
  final int failedCount;
  final DateTime? refreshedAt;

  Map<String, Object?> toMap() {
    return {
      'enabled': enabled,
      'hostId': hostId,
      'alias': alias,
      'failedCount': failedCount,
      'refreshedAtMillis': refreshedAt?.toUtc().millisecondsSinceEpoch,
      'text': formatHomeWidget(this),
    };
  }
}

HomeWidgetSnapshot pickWorstHostSnapshot(
  List<Host> hosts, {
  required bool enabled,
  DateTime? now,
}) {
  if (!enabled) {
    return const HomeWidgetSnapshot(enabled: false);
  }
  if (hosts.isEmpty) {
    return const HomeWidgetSnapshot(enabled: true);
  }
  final ranked = sortByAttention(hosts);
  return HomeWidgetSnapshot(
    enabled: true,
    hostId: ranked.first.id,
    alias: ranked.first.alias,
    failedCount: ranked.first.failedUnitCount ?? 0,
    refreshedAt: ranked.first.attentionAt,
  );
}

String formatHomeWidget(HomeWidgetSnapshot snap, {DateTime? now}) {
  if (!snap.enabled) {
    return 'Widget off';
  }
  final alias = snap.alias;
  if (alias == null || alias.isEmpty) {
    return 'No hosts';
  }
  final at = snap.refreshedAt;
  final age = at == null ? 'never' : Host.ageLabel(at, now: now);
  return '$alias\n${snap.failedCount} failed · $age';
}
