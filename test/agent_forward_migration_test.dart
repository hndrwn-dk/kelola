import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 23 adds hosts.agent_forward default off', () async {
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
    raw.execute('PRAGMA user_version = 22');
    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 23);
    final cols = await db.customSelect('PRAGMA table_info(hosts)').get();
    expect(
      cols.map((r) => r.read<String>('name')).contains('agent_forward'),
      isTrue,
    );
  });

  test('repository stores agent forward and defaults off', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final host = await hosts.insert(
      alias: 'web',
      address: '10.0.0.8',
      port: 22,
      username: 'ops',
    );
    expect((await hosts.get(host.id))!.agentForward, isFalse);
    await hosts.setAgentForward(host.id, true);
    expect((await hosts.get(host.id))!.agentForward, isTrue);
  });
}
