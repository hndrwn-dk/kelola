import 'package:drift/drift.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

class TunnelRepository {
  TunnelRepository(this._db);

  final KelolaDatabase _db;

  static const int defaultIdleMinutes = 10;
  static const int minIdleMinutes = 2;
  static const int maxIdleMinutes = 60;

  Stream<List<TunnelTarget>> watchForHost(String hostId) {
    final query = _db.select(_db.tunnelTargets)
      ..where((t) => t.hostId.equals(hostId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.label),
        (t) => OrderingTerm.asc(t.remotePort),
      ]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  /// One-shot read for tests and non-stream callers.
  Future<List<TunnelTarget>> listForHost(String hostId) async {
    final query = _db.select(_db.tunnelTargets)
      ..where((t) => t.hostId.equals(hostId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.label),
        (t) => OrderingTerm.asc(t.remotePort),
      ]);
    final rows = await query.get();
    return rows.map(_fromRow).toList();
  }

  Future<void> upsert(TunnelTarget target) {
    return _db.into(_db.tunnelTargets).insertOnConflictUpdate(
          TunnelTargetsCompanion.insert(
            id: target.id,
            hostId: target.hostId,
            label: target.label,
            remoteHost: target.remoteHost,
            remotePort: target.remotePort,
            scheme: target.scheme.value,
            path: Value(target.path),
          ),
        );
  }

  Future<void> delete(String id) {
    return (_db.delete(_db.tunnelTargets)..where((t) => t.id.equals(id))).go();
  }

  Future<int> idleMinutes() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    final raw = row?.tunnelIdleMinutes ?? defaultIdleMinutes;
    return _clampIdle(raw);
  }

  Future<void> setIdleMinutes(int minutes) async {
    final clamped = _clampIdle(minutes);
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            tunnelIdleMinutes: Value(clamped),
          ),
        );
  }

  static int _clampIdle(int minutes) {
    if (minutes < minIdleMinutes) return minIdleMinutes;
    if (minutes > maxIdleMinutes) return maxIdleMinutes;
    return minutes;
  }

  TunnelTarget _fromRow(TunnelTargetRow row) {
    final scheme = TunnelScheme.parse(row.scheme) ?? TunnelScheme.http;
    return TunnelTarget(
      id: row.id,
      hostId: row.hostId,
      label: row.label,
      remoteHost: row.remoteHost,
      remotePort: row.remotePort,
      scheme: scheme,
      path: row.path,
    );
  }
}
