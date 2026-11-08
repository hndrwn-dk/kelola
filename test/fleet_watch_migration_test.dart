import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 20 adds fleet watch settings and fingerprint table', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
CREATE TABLE app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  last_host_id TEXT NULL,
  public_key_spki_b64 TEXT NULL,
  key_backend TEXT NULL,
  widget_enabled INTEGER NOT NULL DEFAULT 0 CHECK (widget_enabled IN (0, 1)),
  llm_provider TEXT NOT NULL DEFAULT 'none',
  tunnel_idle_minutes INTEGER NOT NULL DEFAULT 10,
  snippet_library_ready INTEGER NOT NULL DEFAULT 0,
  app_lock_timeout_sec INTEGER NOT NULL DEFAULT 0,
  session_log_retention_days INTEGER NOT NULL DEFAULT 14
);
''');
    raw.execute('INSERT INTO app_settings (id) VALUES (1)');
    raw.execute('PRAGMA user_version = 19');

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], db.schemaVersion);

    final settings = await db.customSelect(
      'SELECT fleet_watch_enabled, fleet_watch_disk_percent FROM app_settings WHERE id = 1',
    ).getSingle();
    expect(settings.data['fleet_watch_enabled'], 0);
    expect(settings.data['fleet_watch_disk_percent'], 90);

    final table = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='fleet_watch_state'",
    ).get();
    expect(table, isNotEmpty);
  });
}
