import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:kelola/data/db/tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Hosts, HostKeys, CachedFacts, Recents, Pins, AuditRecords, AppSettings],
)
class KelolaDatabase extends _$KelolaDatabase {
  KelolaDatabase() : super(driftDatabase(name: 'kelola'));

  KelolaDatabase.memory() : super(NativeDatabase.memory());

  KelolaDatabase.connect(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(hosts, hosts.failedUnitCount);
            await m.addColumn(hosts, hosts.diskRootPercent);
            await m.addColumn(hosts, hosts.attentionAt);
          }
          if (from < 3) {
            await m.addColumn(auditRecords, auditRecords.title);
          }
          if (from < 4) {
            await m.addColumn(hosts, hosts.sudoNeedsPassword);
          }
        },
      );
}
