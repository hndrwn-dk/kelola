import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';

/// Persist failed-unit names after a dashboard probe succeeds.
/// Search never calls this — only [SshSessionPool.execute] after parse.
/// Unit and container lists stay on their host screens and are not indexed.
Future<void> writeSearchIndexFromProbe({
  required HostRepository repo,
  required String hostId,
  required Object? parsed,
  DateTime? now,
}) {
  if (parsed is DashboardSnapshot) {
    return repo.replaceSearchFailedUnits(
      hostId: hostId,
      names: parsed.failedUnitNames,
      at: (now ?? DateTime.now()).toUtc(),
    );
  }
  return Future<void>.value();
}
