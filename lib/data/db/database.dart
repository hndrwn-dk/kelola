import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:kelola/data/db/tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Hosts,
    HostKeys,
    CachedFacts,
    Recents,
    Pins,
    AuditRecords,
    AppSettings,
    SearchIndexCache,
    Snippets,
    HostTags,
    FleetCache,
  ],
)
class KelolaDatabase extends _$KelolaDatabase {
  KelolaDatabase() : super(driftDatabase(name: 'kelola'));

  KelolaDatabase.memory() : super(NativeDatabase.memory());

  KelolaDatabase.connect(super.e);

  @override
  int get schemaVersion => 9;

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
          if (from < 5) {
            await m.createTable(searchIndexCache);
          }
          if (from < 6) {
            await m.createTable(snippets);
          }
          if (from < 7) {
            await m.addColumn(appSettings, appSettings.widgetEnabled);
          }
          if (from < 8) {
            await m.addColumn(appSettings, appSettings.llmProvider);
            await m.addColumn(appSettings, appSettings.llmBaseUrl);
            await m.addColumn(appSettings, appSettings.llmApiKey);
            await m.addColumn(appSettings, appSettings.llmModel);
          }
          if (from < 9) {
            await m.createTable(hostTags);
            await m.createTable(fleetCache);
          }
        },
      );
}
