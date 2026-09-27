import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 18 adds session logs, bookmarks, and retention days', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
CREATE TABLE hosts (
  id TEXT NOT NULL PRIMARY KEY,
  alias TEXT NOT NULL,
  address TEXT NOT NULL,
  port INTEGER NOT NULL DEFAULT 22,
  username TEXT NOT NULL,
  key_alias TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
''');
    raw.execute('''
CREATE TABLE app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  last_host_id TEXT NULL,
  public_key_spki_b64 TEXT NULL,
  key_backend TEXT NULL,
  widget_enabled INTEGER NOT NULL DEFAULT 0 CHECK (widget_enabled IN (0, 1)),
  llm_provider TEXT NOT NULL DEFAULT 'none',
  llm_base_url TEXT NULL,
  llm_api_key TEXT NULL,
  llm_model TEXT NULL,
  llm_ollama_base_url TEXT NULL,
  llm_ollama_model TEXT NULL,
  llm_openai_base_url TEXT NULL,
  llm_openai_api_key TEXT NULL,
  llm_openai_model TEXT NULL,
  tunnel_idle_minutes INTEGER NOT NULL DEFAULT 10,
  snippet_library_ready INTEGER NOT NULL DEFAULT 0,
  app_lock_timeout_sec INTEGER NOT NULL DEFAULT 0
);
''');
    raw.execute('INSERT INTO app_settings (id) VALUES (1)');
    raw.execute('PRAGMA user_version = 17');

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 19);

    final logCols = await db.customSelect('PRAGMA table_info(session_logs)').get();
    expect(
      logCols.map((r) => r.read<String>('name')).toSet(),
      containsAll(['id', 'host_id', 'title', 'body', 'created_at', 'bookmarked']),
    );

    final markCols =
        await db.customSelect('PRAGMA table_info(journal_bookmarks)').get();
    expect(
      markCols.map((r) => r.read<String>('name')).toSet(),
      containsAll(['id', 'host_id', 'label', 'query', 'scope', 'last_hour']),
    );

    final row = await db
        .customSelect(
          'SELECT session_log_retention_days FROM app_settings WHERE id = 1',
        )
        .getSingle();
    expect(row.data['session_log_retention_days'], 14);
  });
}
