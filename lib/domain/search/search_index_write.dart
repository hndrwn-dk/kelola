import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/units/service_unit.dart';

/// Persist a local search index after a list probe succeeds.
/// Search never calls this — only [SshSessionPool.execute] after parse.
Future<void> writeSearchIndexFromProbe({
  required HostRepository repo,
  required String hostId,
  required Object? parsed,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  if (parsed is DashboardSnapshot) {
    return repo.replaceSearchFailedUnits(
      hostId: hostId,
      names: parsed.failedUnitNames,
      at: at,
    );
  }
  if (parsed is UnitListResult) {
    return repo.replaceSearchUnits(
      hostId: hostId,
      names: parsed.units.map((u) => u.name).toList(),
      at: at,
    );
  }
  if (parsed is ContainerInventory) {
    return repo.replaceSearchContainers(
      hostId: hostId,
      names: parsed.rows.map((r) => r.title).toList(),
      at: at,
    );
  }
  return Future<void>.value();
}
