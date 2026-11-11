import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';

/// M52 §4: fleet service pills. Pure helpers over the per-host detection
/// cache; nothing here touches SSH.

/// How many of [hostIds] have [ServiceId] in their cached detection (any
/// state). Cache entries for other host ids are ignored. Ids with a zero
/// count are absent; iteration follows catalog order.
Map<ServiceId, int> serviceCounts(
  Map<String, ServiceDetection> cache,
  Iterable<String> hostIds,
) {
  final counts = <ServiceId, int>{};
  for (final hostId in hostIds.toSet()) {
    final detection = cache[hostId];
    if (detection == null) {
      continue;
    }
    for (final id in detection.services.map((s) => s.id).toSet()) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }
  return {
    for (final d in kServiceCatalog)
      if (counts.containsKey(d.id)) d.id: counts[d.id]!,
  };
}

/// No filter matches everything; a filter never matches a host with no
/// cached detection.
bool matchesService(ServiceDetection? d, ServiceId? filter) {
  if (filter == null) {
    return true;
  }
  if (d == null) {
    return false;
  }
  return d.services.any((s) => s.id == filter);
}

/// Short lowercase pill label (FilterPill uppercases it).
String serviceShortLabel(ServiceId id) => switch (id) {
  ServiceId.nginx => 'nginx',
  ServiceId.apache => 'apache',
  ServiceId.mariadb => 'mariadb',
  ServiceId.mysql => 'mysql',
  ServiceId.postgres => 'postgres',
};

String servicePillLabel(ServiceId id, int count) =>
    '${serviceShortLabel(id)} $count';
