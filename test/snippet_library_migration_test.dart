import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

const _v13AppSettings = '''
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
  tunnel_idle_minutes INTEGER NOT NULL DEFAULT 10
);
''';

const _v13Snippets = '''
CREATE TABLE snippets (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  template TEXT NOT NULL,
  starter INTEGER NOT NULL DEFAULT 0 CHECK (starter IN (0, 1)),
  updated_at INTEGER NOT NULL
);
''';

void main() {
  test(
    'schema 14 marks an existing library ready and an empty one unseeded',
    () async {
      final raw = sqlite3.openInMemory();
      raw.execute(_v13AppSettings);
      raw.execute(_v13Snippets);
      raw.execute('INSERT INTO app_settings (id) VALUES (1)');
      raw.execute(
        "INSERT INTO snippets (id, name, template, starter, updated_at) "
        "VALUES ('starter-df', 'df -PT', 'df -PT {{path}}', 1, 0)",
      );
      raw.execute('PRAGMA user_version = 13');

      final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data['user_version'], 14);

      final ready = await db
          .customSelect(
            'SELECT snippet_library_ready FROM app_settings WHERE id = 1',
          )
          .getSingle();
      expect(ready.data['snippet_library_ready'], 1);

      final kept = await db
          .customSelect("SELECT template FROM snippets WHERE id = 'starter-df'")
          .getSingle();
      expect(kept.read<String>('template'), 'df -PT {{path}}');
    },
  );

  test(
    'schema 14 leaves an empty library unseeded so delete-all can stick',
    () async {
      final raw = sqlite3.openInMemory();
      raw.execute(_v13AppSettings);
      raw.execute(_v13Snippets);
      raw.execute('INSERT INTO app_settings (id) VALUES (1)');
      raw.execute('PRAGMA user_version = 13');

      final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final ready = await db
          .customSelect(
            'SELECT snippet_library_ready FROM app_settings WHERE id = 1',
          )
          .getSingle();
      expect(ready.data['snippet_library_ready'], 0);
    },
  );
}
