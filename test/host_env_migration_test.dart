import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 22 creates env_vars and reaches current version', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('PRAGMA user_version = 21');
    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 23);
    final table = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='env_vars'",
    ).get();
    expect(table, isNotEmpty);
  });

  test('repository resolves tag then host env', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final host = await hosts.insert(
      alias: 'web',
      address: '10.0.0.8',
      port: 22,
      username: 'ops',
    );
    await hosts.setHostTags(host.id, ['prod']);
    await hosts.upsertEnvBinding(
      const EnvBinding(
        id: 'tag-1',
        scope: EnvScope.tag,
        scopeId: 'prod',
        name: 'ROLE',
        value: 'api',
      ),
    );
    await hosts.upsertEnvBinding(
      EnvBinding(
        id: 'host-1',
        scope: EnvScope.host,
        scopeId: host.id,
        name: 'ROLE',
        value: 'worker',
      ),
    );
    final tagged = (await hosts.get(host.id))!;
    expect(await hosts.envForHost(tagged), {'ROLE': 'worker'});
    await hosts.deleteEnvBinding('host-1');
    expect(await hosts.envForHost(tagged), {'ROLE': 'api'});
  });
}
