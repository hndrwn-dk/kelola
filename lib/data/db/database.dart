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
  int get schemaVersion => 11;

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
          // Schema 9 fleet_cache lacked extended columns; fresh <9 createAll already has them.
          if (from == 9) {
            await m.addColumn(fleetCache, fleetCache.nprocCores);
            await m.addColumn(fleetCache, fleetCache.memPercent);
            await m.addColumn(fleetCache, fleetCache.highDiskJson);
            await m.addColumn(fleetCache, fleetCache.securityUpdates);
            await m.addColumn(fleetCache, fleetCache.containersDown);
            await m.addColumn(fleetCache, fleetCache.containersUnhealthy);
            await m.addColumn(fleetCache, fleetCache.uptimeSeconds);
            await m.addColumn(fleetCache, fleetCache.rebootRequired);
          }
          if (from < 11) {
            await m.addColumn(appSettings, appSettings.llmOllamaBaseUrl);
            await m.addColumn(appSettings, appSettings.llmOllamaModel);
            await m.addColumn(appSettings, appSettings.llmOpenaiBaseUrl);
            await m.addColumn(appSettings, appSettings.llmOpenaiApiKey);
            await m.addColumn(appSettings, appSettings.llmOpenaiModel);
            await customStatement('''
UPDATE app_settings SET
  llm_ollama_base_url = CASE
    WHEN llm_provider = 'ollama' THEN llm_base_url
    ELSE llm_ollama_base_url END,
  llm_ollama_model = CASE
    WHEN llm_provider = 'ollama' THEN llm_model
    ELSE llm_ollama_model END,
  llm_openai_base_url = CASE
    WHEN llm_provider IN ('openaiCompatible', 'openai') THEN llm_base_url
    ELSE llm_openai_base_url END,
  llm_openai_api_key = CASE
    WHEN llm_provider IN ('openaiCompatible', 'openai') THEN llm_api_key
    ELSE llm_openai_api_key END,
  llm_openai_model = CASE
    WHEN llm_provider IN ('openaiCompatible', 'openai') THEN llm_model
    ELSE llm_openai_model END
''');
          }
        },
      );
}
