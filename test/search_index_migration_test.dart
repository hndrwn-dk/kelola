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

void main() {
  test('onUpgrade from schema 4 creates search_index', () async {
    final raw = sqlite3.openInMemory();
    raw.execute(_v4HostsSql);
    raw.execute(_v4AppSettingsSql);
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

    final tablesAfter = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='search_index'",
    ).get();
    expect(tablesAfter, isNotEmpty);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 7);

    final cols = await db.customSelect('PRAGMA table_info(search_index)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names, containsAll(['host_id', 'kind', 'name', 'indexed_at']));

    final settingsCols =
        await db.customSelect('PRAGMA table_info(app_settings)').get();
    expect(
      settingsCols.map((r) => r.read<String>('name')).toSet(),
      contains('widget_enabled'),
    );
  });
}
