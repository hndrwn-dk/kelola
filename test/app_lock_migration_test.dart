import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:sqlite3/sqlite3.dart';

const _v14AppSettings = '''
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
  snippet_library_ready INTEGER NOT NULL DEFAULT 0
    CHECK (snippet_library_ready IN (0, 1))
);
''';

void main() {
  test('schema 15 adds app_lock_timeout_sec default 0', () async {
    final raw = sqlite3.openInMemory();
    raw.execute(_v14AppSettings);
    raw.execute('''
CREATE TABLE snippets (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  template TEXT NOT NULL,
  starter INTEGER NOT NULL DEFAULT 0 CHECK (starter IN (0, 1)),
  updated_at INTEGER NOT NULL
);
''');
    raw.execute('INSERT INTO app_settings (id) VALUES (1)');
    raw.execute('PRAGMA user_version = 14');

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 24);

    final row = await db
        .customSelect(
          'SELECT app_lock_timeout_sec FROM app_settings WHERE id = 1',
        )
        .getSingle();
    expect(row.data['app_lock_timeout_sec'], 0);
  });

  test('app lock timeout defaults to off and round-trips', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    expect(await repo.appLockTimeoutSec(), 0);
    await repo.setAppLockTimeoutSec(-1);
    expect(await repo.appLockTimeoutSec(), -1);
    await repo.setAppLockTimeoutSec(60);
    expect(await repo.appLockTimeoutSec(), 60);
  });
}
