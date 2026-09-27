import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 16 creates command_history', () async {
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
CREATE TABLE snippets (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  template TEXT NOT NULL,
  starter INTEGER NOT NULL DEFAULT 0 CHECK (starter IN (0, 1)),
  updated_at INTEGER NOT NULL
);
''');
    raw.execute('PRAGMA user_version = 15');

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 21);

    final cols = await db
        .customSelect('PRAGMA table_info(command_history)')
        .get();
    expect(
      cols.map((r) => r.read<String>('name')).toSet(),
      containsAll(['host_id', 'command', 'used_at']),
    );
  });
}
