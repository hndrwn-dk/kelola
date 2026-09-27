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
    TunnelTargets,
    CommandHistory,
    SessionLogs,
    JournalBookmarks,
    FleetWatchState,
    VaultTombstones,
    EnvVars,
  ],
)
class KelolaDatabase extends _$KelolaDatabase {
  KelolaDatabase() : super(driftDatabase(name: 'kelola'));

  KelolaDatabase.memory() : super(NativeDatabase.memory());

  KelolaDatabase.connect(super.e);

  @override
  int get schemaVersion => 23;

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
      // Only exact-9 needs ALTER: from < 9 createTable(fleet_cache) already emits the wide table.
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
      if (from < 12) {
        await m.addColumn(cachedFacts, cachedFacts.journalAccess);
        await customStatement('''
UPDATE cached_facts SET journal_access = CASE
  WHEN journal_readable = 1 THEN 'plain'
  ELSE 'unknown' END
''');
      }
      if (from < 13) {
        await m.createTable(tunnelTargets);
        await m.addColumn(appSettings, appSettings.tunnelIdleMinutes);
        await m.addColumn(auditRecords, auditRecords.closeReason);
      }
      if (from < 14) {
        await m.addColumn(appSettings, appSettings.snippetLibraryReady);
        await customStatement('''
INSERT INTO app_settings (id, snippet_library_ready)
SELECT 1, CASE WHEN (SELECT COUNT(*) FROM snippets) > 0 THEN 1 ELSE 0 END
WHERE NOT EXISTS (SELECT 1 FROM app_settings WHERE id = 1)
''');
        await customStatement('''
UPDATE app_settings
SET snippet_library_ready = CASE
  WHEN (SELECT COUNT(*) FROM snippets) > 0 THEN 1
  ELSE snippet_library_ready
END
WHERE id = 1
''');
      }
      if (from < 15) {
        await m.addColumn(appSettings, appSettings.appLockTimeoutSec);
      }
      if (from < 16) {
        await m.createTable(commandHistory);
      }
      // from < 6 createTable(snippets) already emits host_id / tag / startup.
      if (from >= 6 && from < 17) {
        await m.addColumn(snippets, snippets.hostId);
        await m.addColumn(snippets, snippets.tag);
        await m.addColumn(snippets, snippets.startup);
      }
      if (from < 18) {
        await m.createTable(sessionLogs);
        await m.createTable(journalBookmarks);
        final hasSettings = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='app_settings'",
        ).get();
        if (hasSettings.isNotEmpty) {
          await m.addColumn(
            appSettings,
            appSettings.sessionLogRetentionDays,
          );
        }
      }
      if (from < 19) {
        final hasTunnels = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='tunnel_targets'",
        ).get();
        if (hasTunnels.isNotEmpty) {
          final cols = await customSelect(
            'PRAGMA table_info(tunnel_targets)',
          ).get();
          final names = cols.map((r) => r.read<String>('name')).toSet();
          if (!names.contains('kind')) {
            await m.addColumn(tunnelTargets, tunnelTargets.kind);
          }
        }
      }
      if (from < 20) {
        await m.createTable(fleetWatchState);
        final hasSettings = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='app_settings'",
        ).get();
        if (hasSettings.isNotEmpty) {
          final cols = await customSelect(
            'PRAGMA table_info(app_settings)',
          ).get();
          final names = cols.map((r) => r.read<String>('name')).toSet();
          if (!names.contains('fleet_watch_enabled')) {
            await m.addColumn(appSettings, appSettings.fleetWatchEnabled);
            await m.addColumn(appSettings, appSettings.fleetWatchDiskPercent);
            await m.addColumn(appSettings, appSettings.fleetWatchMemPercent);
            await m.addColumn(appSettings, appSettings.fleetWatchFailedUnits);
            await m.addColumn(appSettings, appSettings.fleetWatchContainers);
            await m.addColumn(appSettings, appSettings.fleetWatchReboot);
            await m.addColumn(appSettings, appSettings.fleetWatchLastTickAt);
          }
        }
      }
      if (from < 21) {
        await m.createTable(vaultTombstones);
        final hasHosts = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='hosts'",
        ).get();
        if (hasHosts.isNotEmpty) {
          final hostCols = await customSelect('PRAGMA table_info(hosts)').get();
          final hostNames = hostCols.map((r) => r.read<String>('name')).toSet();
          if (!hostNames.contains('updated_at')) {
            await m.addColumn(hosts, hosts.updatedAt);
            await customStatement(
              'UPDATE hosts SET updated_at = created_at WHERE updated_at IS NULL',
            );
          }
        }
        final hasSettings = await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name='app_settings'",
        ).get();
        if (hasSettings.isNotEmpty) {
          final cols = await customSelect(
            'PRAGMA table_info(app_settings)',
          ).get();
          final names = cols.map((r) => r.read<String>('name')).toSet();
          if (!names.contains('device_id')) {
            await m.addColumn(appSettings, appSettings.deviceId);
            await m.addColumn(appSettings, appSettings.vaultIncludeSecrets);
          }
        }
      }
      if (from < 22) {
        await m.createTable(envVars);
      }
      if (from < 23) {
        final tables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='hosts'",
        ).get();
        if (tables.isNotEmpty) {
          final cols = await customSelect('PRAGMA table_info(hosts)').get();
          final names = cols.map((r) => r.read<String>('name')).toSet();
          if (!names.contains('agent_forward')) {
            await m.addColumn(hosts, hosts.agentForward);
          }
        }
      }
    },
  );
}
