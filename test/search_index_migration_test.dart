import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Hosts table as of schema 4 (attention / attention_at / sudo_needs_password).
const _v4HostsSql = '''
CREATE TABLE hosts (
  id TEXT NOT NULL PRIMARY KEY,
  alias TEXT NOT NULL,
  address TEXT NOT NULL,
  port INTEGER NOT NULL DEFAULT 22,
  username TEXT NOT NULL,
  key_alias TEXT NOT NULL,
  jump_host_id TEXT NULL,
  read_only INTEGER NOT NULL DEFAULT 0 CHECK (read_only IN (0, 1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  note TEXT NULL,
  last_rtt_ms INTEGER NULL,
  attention TEXT NOT NULL DEFAULT 'unknown',
  failed_unit_count INTEGER NULL,
  disk_root_percent INTEGER NULL,
  attention_at INTEGER NULL,
  last_seen_at INTEGER NULL,
  created_at INTEGER NOT NULL,
  sudo_needs_password INTEGER NOT NULL DEFAULT 0
    CHECK (sudo_needs_password IN (0, 1))
);
''';

const _v4AppSettingsSql = '''
CREATE TABLE app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  last_host_id TEXT NULL,
  public_key_spki_b64 TEXT NULL,
  key_backend TEXT NULL
);
''';

/// audit_records as of schema 4 (pre close_reason; from < 13 adds that column).
const _v4AuditRecordsSql = '''
CREATE TABLE audit_records (
  id TEXT NOT NULL PRIMARY KEY,
  timestamp_utc INTEGER NOT NULL,
  host_id TEXT NOT NULL,
  host_alias TEXT NOT NULL,
  remote_user TEXT NOT NULL,
  command TEXT NOT NULL,
  risk TEXT NOT NULL,
  used_sudo INTEGER NOT NULL CHECK (used_sudo IN (0, 1)),
  exit_code INTEGER NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  error_summary TEXT NULL,
  app_version TEXT NOT NULL
);
''';

/// cached_facts as of schema 4 (pre journal_access; from < 12 adds that column).
const _v4CachedFactsSql = '''
CREATE TABLE cached_facts (
  host_id TEXT NOT NULL PRIMARY KEY,
  os_id TEXT NOT NULL,
  os_version_id TEXT NOT NULL,
  pretty_name TEXT NULL,
  init_system TEXT NOT NULL,
  systemd_version INTEGER NULL,
  pkg TEXT NOT NULL,
  fw TEXT NOT NULL,
  has_journald INTEGER NOT NULL CHECK (has_journald IN (0, 1)),
  journal_readable INTEGER NOT NULL CHECK (journal_readable IN (0, 1)),
  arch TEXT NOT NULL,
  discovered_at INTEGER NOT NULL
);
''';

/// Full schema 1 (621ef12) — Drift-quoted form matching createAll style.
const _v1SchemaSql = '''
CREATE TABLE "hosts" ("id" TEXT NOT NULL, "alias" TEXT NOT NULL, "address" TEXT NOT NULL, "port" INTEGER NOT NULL DEFAULT 22, "username" TEXT NOT NULL, "key_alias" TEXT NOT NULL, "jump_host_id" TEXT NULL, "read_only" INTEGER NOT NULL DEFAULT 0 CHECK ("read_only" IN (0, 1)), "sort_order" INTEGER NOT NULL DEFAULT 0, "note" TEXT NULL, "last_rtt_ms" INTEGER NULL, "attention" TEXT NOT NULL DEFAULT 'unknown', "last_seen_at" INTEGER NULL, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "host_keys" ("host_id" TEXT NOT NULL, "algorithm" TEXT NOT NULL, "fingerprint" TEXT NOT NULL, "pinned_at" INTEGER NOT NULL, PRIMARY KEY ("host_id"));
CREATE TABLE "cached_facts" ("host_id" TEXT NOT NULL, "os_id" TEXT NOT NULL, "os_version_id" TEXT NOT NULL, "pretty_name" TEXT NULL, "init_system" TEXT NOT NULL, "systemd_version" INTEGER NULL, "pkg" TEXT NOT NULL, "fw" TEXT NOT NULL, "has_journald" INTEGER NOT NULL CHECK ("has_journald" IN (0, 1)), "journal_readable" INTEGER NOT NULL CHECK ("journal_readable" IN (0, 1)), "arch" TEXT NOT NULL, "discovered_at" INTEGER NOT NULL, PRIMARY KEY ("host_id"));
CREATE TABLE "recents" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "kind" TEXT NOT NULL, "host_id" TEXT NOT NULL, "label" TEXT NOT NULL, "viewed_at" INTEGER NOT NULL);
CREATE TABLE "pins" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "host_id" TEXT NOT NULL, "kind" TEXT NOT NULL, "label" TEXT NOT NULL, "route" TEXT NOT NULL, "sort_order" INTEGER NOT NULL);
CREATE TABLE "audit_records" ("id" TEXT NOT NULL, "timestamp_utc" INTEGER NOT NULL, "host_id" TEXT NOT NULL, "host_alias" TEXT NOT NULL, "remote_user" TEXT NOT NULL, "command" TEXT NOT NULL, "risk" TEXT NOT NULL, "used_sudo" INTEGER NOT NULL CHECK ("used_sudo" IN (0, 1)), "exit_code" INTEGER NULL, "duration_ms" INTEGER NOT NULL DEFAULT 0, "error_summary" TEXT NULL, "app_version" TEXT NOT NULL, PRIMARY KEY ("id"));
CREATE TABLE "app_settings" ("id" INTEGER NOT NULL, "last_host_id" TEXT NULL, "public_key_spki_b64" TEXT NULL, "key_backend" TEXT NULL, PRIMARY KEY ("id"));
''';

Future<Map<String, Object?>> _schemaSnapshot(KelolaDatabase db) async {
  final version = await db.customSelect('PRAGMA user_version').getSingle();
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' "
        "ORDER BY name",
      )
      .get();
  final tableNames = tables.map((r) => r.read<String>('name')).toList();

  final columns = <String, List<Map<String, Object?>>>{};
  for (final name in tableNames) {
    final cols = await db.customSelect('PRAGMA table_info("$name")').get();
    final list =
        cols
            .map(
              (c) => <String, Object?>{
                'name': c.read<String>('name'),
                'type': c.read<String>('type'),
                'notnull': c.read<int>('notnull'),
                'dflt_value': c.data['dflt_value'],
                'pk': c.read<int>('pk'),
              },
            )
            .toList()
          ..sort(
            (a, b) => (a['name']! as String).compareTo(b['name']! as String),
          );
    columns[name] = list;
  }

  final indexes = await db
      .customSelect(
        "SELECT name, tbl_name, sql FROM sqlite_master "
        "WHERE type = 'index' AND name NOT LIKE 'sqlite_%' "
        "ORDER BY name",
      )
      .get();
  final indexList = indexes
      .map(
        (r) => <String, Object?>{
          'name': r.read<String>('name'),
          'tbl_name': r.read<String>('tbl_name'),
          'sql': r.read<String?>('sql'),
        },
      )
      .toList();

  return {
    'user_version': version.data['user_version'],
    'tables': tableNames,
    'columns': columns,
    'indexes': indexList,
  };
}

void main() {
  test('onUpgrade from schema 4 creates search_index', () async {
    final raw = sqlite3.openInMemory();
    raw.execute(_v4HostsSql);
    raw.execute(_v4AppSettingsSql);
    raw.execute(_v4AuditRecordsSql);
    raw.execute(_v4CachedFactsSql);
    raw.execute('PRAGMA user_version = 4');

    final tablesBefore = raw
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='search_index'",
        )
        .map((r) => r['name'])
        .toList();
    expect(tablesBefore, isEmpty);
    expect(raw.select('PRAGMA user_version').first['user_version'], 4);

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final tablesAfter = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='search_index'",
        )
        .get();
    expect(tablesAfter, isNotEmpty);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 14);

    final cols = await db.customSelect('PRAGMA table_info(search_index)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['host_id', 'kind', 'name', 'indexed_at']));

    final settingsCols = await db
        .customSelect('PRAGMA table_info(app_settings)')
        .get();
    expect(
      settingsCols.map((r) => r.read<String>('name')).toSet(),
      containsAll([
        'widget_enabled',
        'tunnel_idle_minutes',
        'snippet_library_ready',
      ]),
    );

    final tagTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='host_tags'",
        )
        .get();
    expect(tagTable, isNotEmpty);
    final fleetTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='fleet_cache'",
        )
        .get();
    expect(fleetTable, isNotEmpty);

    final fleetCols = await db
        .customSelect('PRAGMA table_info(fleet_cache)')
        .get();
    expect(
      fleetCols.map((r) => r.read<String>('name')).toSet(),
      containsAll(['mem_percent', 'security_updates', 'containers_down']),
    );

    final tunnelTable = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='tunnel_targets'",
        )
        .get();
    expect(tunnelTable, isNotEmpty);

    final auditCols = await db
        .customSelect('PRAGMA table_info(audit_records)')
        .get();
    expect(
      auditCols.map((r) => r.read<String>('name')).toSet(),
      contains('close_reason'),
    );
  });

  test('onCreate current schema matches schema migrated from v1', () async {
    final created = KelolaDatabase.memory();
    addTearDown(created.close);
    await created.customSelect('SELECT 1').get();

    final raw = sqlite3.openInMemory();
    for (final stmt
        in _v1SchemaSql
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)) {
      raw.execute(stmt);
    }
    raw.execute('PRAGMA user_version = 1');
    final migrated = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(migrated.close);
    await migrated.customSelect('SELECT 1').get();

    final a = await _schemaSnapshot(created);
    final b = await _schemaSnapshot(migrated);

    expect(b['user_version'], a['user_version'], reason: 'user_version');
    expect(b['tables'], a['tables'], reason: 'tables');
    expect(b['indexes'], a['indexes'], reason: 'indexes');

    final colsA = a['columns']! as Map<String, List<Map<String, Object?>>>;
    final colsB = b['columns']! as Map<String, List<Map<String, Object?>>>;
    expect(
      colsB.keys.toList()..sort(),
      colsA.keys.toList()..sort(),
      reason: 'column table keys',
    );
    for (final table in colsA.keys) {
      expect(colsB[table], colsA[table], reason: 'columns for $table');
    }
  });
}
