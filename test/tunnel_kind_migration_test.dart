import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 19 adds tunnel_targets.kind defaulting to local', () async {
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
CREATE TABLE tunnel_targets (
  id TEXT NOT NULL PRIMARY KEY,
  host_id TEXT NOT NULL REFERENCES hosts (id),
  label TEXT NOT NULL,
  remote_host TEXT NOT NULL,
  remote_port INTEGER NOT NULL,
  scheme TEXT NOT NULL,
  path TEXT NOT NULL DEFAULT ''
);
''');
    raw.execute(
      "INSERT INTO hosts (id, alias, address, port, username, key_alias, created_at) "
      "VALUES ('h1', 'web-01', '10.0.0.1', 22, 'deploy', 'k', 0)",
    );
    raw.execute(
      "INSERT INTO tunnel_targets (id, host_id, label, remote_host, remote_port, scheme, path) "
      "VALUES ('t1', 'h1', 'Cockpit', '127.0.0.1', 9090, 'https', '/')",
    );
    raw.execute('PRAGMA user_version = 18');

    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 22);

    final cols = await db.customSelect('PRAGMA table_info(tunnel_targets)').get();
    expect(cols.map((r) => r.read<String>('name')).toSet(), contains('kind'));

    final row = await db
        .customSelect("SELECT kind FROM tunnel_targets WHERE id = 't1'")
        .getSingle();
    expect(row.data['kind'], 'local');
  });

  test('repository persists kind and defaults missing rows to local', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final tunnels = TunnelRepository(db);
    final host = await hosts.insert(
      alias: 'web-01',
      address: '10.0.0.1',
      port: 22,
      username: 'deploy',
    );

    await tunnels.upsert(
      TunnelTarget(
        id: 'socks',
        hostId: host.id,
        label: 'Proxy',
        remoteHost: '',
        remotePort: 0,
        scheme: TunnelScheme.http,
        path: '',
        kind: TunnelKind.dynamic,
      ),
    );
    await tunnels.upsert(
      TunnelTarget(
        id: 'kfwd',
        hostId: host.id,
        label: 'nginx',
        remoteHost: 'svc/nginx',
        remotePort: 80,
        scheme: TunnelScheme.http,
        path: 'default',
        kind: TunnelKind.kubectl,
      ),
    );

    final listed = await tunnels.listForHost(host.id);
    expect(listed.map((t) => t.kind).toSet(), {
      TunnelKind.dynamic,
      TunnelKind.kubectl,
    });
    expect(
      listed.firstWhere((t) => t.id == 'kfwd').remoteHost,
      'svc/nginx',
    );
  });
}
