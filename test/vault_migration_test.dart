import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/vault/vault_store.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('schema 21 onCreate has vault columns and tombstones', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 24);
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='vault_tombstones'",
    ).get();
    expect(tables, isNotEmpty);
    final cols = await db.customSelect('PRAGMA table_info(app_settings)').get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names.contains('device_id'), isTrue);
    expect(names.contains('vault_include_secrets'), isTrue);
    final hostCols = await db.customSelect('PRAGMA table_info(hosts)').get();
    expect(
      hostCols.map((r) => r.read<String>('name')).contains('updated_at'),
      isTrue,
    );
  });

  test('upgrade from 20 adds vault columns', () async {
    final raw = sqlite3.openInMemory();
    raw.execute('''
CREATE TABLE app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  last_host_id TEXT NULL,
  public_key_spki_b64 TEXT NULL,
  key_backend TEXT NULL,
  widget_enabled INTEGER NOT NULL DEFAULT 0,
  llm_provider TEXT NOT NULL DEFAULT 'none'
);
''');
    raw.execute('INSERT INTO app_settings (id) VALUES (1)');
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
    raw.execute('PRAGMA user_version = 20');
    final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data['user_version'], 24);
    final settings = await db.customSelect(
      'SELECT vault_include_secrets FROM app_settings WHERE id = 1',
    ).getSingle();
    expect(settings.data['vault_include_secrets'], 0);
  });

  test('vault store round-trips a host without secrets', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final store = VaultStore(
      db: db,
      hosts: hosts,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
    );
    await hosts.insert(
      alias: 'nas-01',
      address: '10.0.0.8',
      port: 22,
      username: 'ops',
    );
    await hosts.upsertEnvBinding(
      const EnvBinding(
        id: 'env-1',
        scope: EnvScope.tag,
        scopeId: 'prod',
        name: 'ROLE',
        value: 'api',
      ),
    );
    final snap = await store.snapshot();
    expect(snap.includeSecrets, isFalse);
    expect(snap.records.where((r) => r.kind.name == 'host'), isNotEmpty);
    expect(snap.records.where((r) => r.kind.name == 'env'), isNotEmpty);
    expect(
      snap.records
          .where((r) => r.kind.name == 'host')
          .every((r) => !r.payload.containsKey('password')),
      isTrue,
    );
    expect(await store.deviceId(), isNotEmpty);
    final env = snap.records.singleWhere((r) => r.kind == VaultRecordKind.env);
    expect(env.payload['name'], 'ROLE');
    expect(env.payload.containsKey('value'), isFalse);
  });

  test('vault apply refuses to overwrite or delete existing host-key pins',
      () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final store = VaultStore(
      db: db,
      hosts: hosts,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
    );
    final host = await hosts.insert(
      alias: 'edge',
      address: '10.0.0.9',
      port: 22,
      username: 'ops',
    );
    await hosts.pinKey(
      hostId: host.id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:good',
    );
    await store.apply(
      VaultDiff(
        added: const [],
        updated: [
          VaultRecord(
            id: host.id,
            kind: VaultRecordKind.hostKey,
            updatedAt: DateTime.utc(2030, 1, 1),
            deviceId: 'attacker',
            payload: const {
              'algorithm': 'ssh-ed25519',
              'fingerprint': 'SHA256:evil',
            },
          ),
        ],
        deleted: [
          VaultRecord(
            id: host.id,
            kind: VaultRecordKind.hostKey,
            updatedAt: DateTime.utc(2030, 1, 2),
            deviceId: 'attacker',
            payload: const {},
            tombstone: true,
          ),
        ],
      ),
    );
    final pin = await hosts.pinnedKey(host.id);
    expect(pin?.fingerprint, 'SHA256:good');
  });

  test('vault apply never enables agent forwarding from a blob', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final store = VaultStore(
      db: db,
      hosts: hosts,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
    );
    await store.apply(
      VaultDiff(
        added: [
          VaultRecord(
            id: 'imported',
            kind: VaultRecordKind.host,
            updatedAt: DateTime.utc(2026, 9, 1),
            deviceId: 'other',
            payload: const {
              'alias': 'jump',
              'address': '10.1.1.1',
              'port': 22,
              'username': 'ops',
              'agentForward': true,
            },
          ),
        ],
        updated: const [],
        deleted: const [],
      ),
    );
    final imported = await hosts.get('imported');
    expect(imported?.agentForward, isFalse);
  });

  test('redacted vault apply keeps local snippet template and env value',
      () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final hosts = HostRepository(db);
    final store = VaultStore(
      db: db,
      hosts: hosts,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
    );
    await hosts.upsertSnippet(
      const Snippet(
        id: 's1',
        name: 'restart',
        template: 'systemctl restart nginx',
      ),
    );
    await hosts.upsertEnvBinding(
      const EnvBinding(
        id: 'e1',
        scope: EnvScope.host,
        scopeId: 'h1',
        name: 'TOKEN',
        value: 'super-secret',
      ),
    );

    final redactedSnippet = packVaultRecords(
      records: [
        VaultRecord(
          id: 's1',
          kind: VaultRecordKind.snippet,
          updatedAt: DateTime.utc(2030, 1, 1),
          deviceId: 'other',
          payload: const {
            'name': 'restart-nginx',
            'template': 'systemctl restart nginx',
          },
        ),
      ],
      deviceId: 'other',
      includeSecrets: false,
    ).records.single;
    final redactedEnv = packVaultRecords(
      records: [
        VaultRecord(
          id: 'e1',
          kind: VaultRecordKind.env,
          updatedAt: DateTime.utc(2030, 1, 1),
          deviceId: 'other',
          payload: const {
            'scope': 'host',
            'scopeId': 'h1',
            'name': 'TOKEN',
            'value': 'super-secret',
          },
        ),
      ],
      deviceId: 'other',
      includeSecrets: false,
    ).records.single;
    expect(redactedSnippet.payload.containsKey('template'), isFalse);
    expect(redactedEnv.payload.containsKey('value'), isFalse);

    await store.apply(
      VaultDiff(
        added: const [],
        updated: [redactedSnippet, redactedEnv],
        deleted: const [],
      ),
    );

    final snippets = await hosts.listSnippets();
    final snippet = snippets.singleWhere((s) => s.id == 's1');
    expect(snippet.name, 'restart-nginx');
    expect(snippet.template, 'systemctl restart nginx');
    final envs = await hosts.listEnvBindings();
    final env = envs.singleWhere((e) => e.id == 'e1');
    expect(env.value, 'super-secret');
  });
}
