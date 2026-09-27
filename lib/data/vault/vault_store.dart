import 'package:drift/drift.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:uuid/uuid.dart';

class VaultStore {
  VaultStore({
    required KelolaDatabase db,
    required HostRepository hosts,
    required TunnelRepository tunnels,
    required Future<FleetProbeSelectionStore> Function() selectionOf,
  }) : _db = db,
       _hosts = hosts,
       _tunnels = tunnels,
       _selectionOf = selectionOf;

  final KelolaDatabase _db;
  final HostRepository _hosts;
  final TunnelRepository _tunnels;
  final Future<FleetProbeSelectionStore> Function() _selectionOf;
  final _uuid = const Uuid();

  Future<String> deviceId() async {
    final row = await _settings();
    final existing = row?.deviceId;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final id = _uuid.v7();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
      _hostsSettingsWrite(row, deviceId: Value(id)),
    );
    return id;
  }

  Future<bool> includeSecrets() async {
    return (await _settings())?.vaultIncludeSecrets ?? false;
  }

  Future<void> setIncludeSecrets(bool value) async {
    final row = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
      _hostsSettingsWrite(row, vaultIncludeSecrets: Value(value)),
    );
  }

  Future<VaultPlaintext> snapshot() async {
    final device = await deviceId();
    final secrets = await includeSecrets();
    final records = <VaultRecord>[
      ...await _hostRecords(device),
      ...await _snippetRecords(device),
      ...await _tagRecords(device),
      ...await _keyRecords(device),
      ...await _tunnelRecords(device),
      ...await _prefRecords(device),
      ...await _envRecords(device),
      ...await _tombstoneRecords(),
    ];
    return packVaultRecords(
      records: records,
      deviceId: device,
      includeSecrets: secrets,
    );
  }

  Future<void> apply(VaultDiff diff) async {
    for (final record in diff.added) {
      await _upsert(record);
    }
    for (final record in diff.updated) {
      await _upsert(record);
    }
    for (final record in diff.deleted) {
      await _delete(record);
    }
  }

  Future<List<VaultRecord>> localRecords() async {
    return (await snapshot()).records;
  }

  Future<List<VaultRecord>> _hostRecords(String device) async {
    final rows = await _db.select(_db.hosts).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.id,
          kind: VaultRecordKind.host,
          updatedAt: (row.updatedAt ?? row.createdAt).toUtc(),
          deviceId: device,
          payload: {
            'alias': row.alias,
            'address': row.address,
            'port': row.port,
            'username': row.username,
            'keyAlias': row.keyAlias,
            'jumpHostId': row.jumpHostId,
            'readOnly': row.readOnly,
            'note': row.note,
            'sortOrder': row.sortOrder,
            'sudoNeedsPassword': row.sudoNeedsPassword,
            'agentForward': row.agentForward,
            'sshCertificate': row.sshCertificate,
          },
        ),
    ];
  }

  Future<List<VaultRecord>> _snippetRecords(String device) async {
    final rows = await _db.select(_db.snippets).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.id,
          kind: VaultRecordKind.snippet,
          updatedAt: row.updatedAt.toUtc(),
          deviceId: device,
          payload: {
            'name': row.name,
            'template': row.template,
            'starter': row.starter,
            'hostId': row.hostId,
            'tag': row.tag,
            'startup': row.startup,
          },
        ),
    ];
  }

  Future<List<VaultRecord>> _tagRecords(String device) async {
    final rows = await _db.select(_db.hostTags).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: '${row.hostId}/${row.tag}',
          kind: VaultRecordKind.hostTag,
          updatedAt: DateTime.now().toUtc(),
          deviceId: device,
          payload: {'hostId': row.hostId, 'tag': row.tag},
        ),
    ];
  }

  Future<List<VaultRecord>> _keyRecords(String device) async {
    final rows = await _db.select(_db.hostKeys).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.hostId,
          kind: VaultRecordKind.hostKey,
          updatedAt: row.pinnedAt.toUtc(),
          deviceId: device,
          payload: {
            'algorithm': row.algorithm,
            'fingerprint': row.fingerprint,
          },
        ),
    ];
  }

  Future<List<VaultRecord>> _tunnelRecords(String device) async {
    final rows = await _db.select(_db.tunnelTargets).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.id,
          kind: VaultRecordKind.tunnel,
          updatedAt: DateTime.now().toUtc(),
          deviceId: device,
          payload: {
            'hostId': row.hostId,
            'label': row.label,
            'remoteHost': row.remoteHost,
            'remotePort': row.remotePort,
            'scheme': row.scheme,
            'path': row.path,
            'kind': row.kind,
          },
        ),
    ];
  }

  Future<List<VaultRecord>> _prefRecords(String device) async {
    final row = await _settings();
    final live = {for (final host in await _hosts.list()) host.id};
    final selected = await (await _selectionOf()).read(live);
    return [
      VaultRecord(
        id: 'prefs',
        kind: VaultRecordKind.pref,
        updatedAt: DateTime.now().toUtc(),
        deviceId: device,
        payload: {
          'widgetEnabled': row?.widgetEnabled ?? false,
          'appLockTimeoutSec': row?.appLockTimeoutSec ?? 0,
          'sessionLogRetentionDays': row?.sessionLogRetentionDays ?? 14,
          'tunnelIdleMinutes': row?.tunnelIdleMinutes ?? 10,
          'fleetWatchEnabled': row?.fleetWatchEnabled ?? false,
          'fleetSelection': selected?.toList(),
        },
      ),
    ];
  }

  Future<List<VaultRecord>> _envRecords(String device) async {
    final rows = await _db.select(_db.envVars).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.id,
          kind: VaultRecordKind.env,
          updatedAt: row.updatedAt.toUtc(),
          deviceId: device,
          payload: {
            'scope': row.scope,
            'scopeId': row.scopeId,
            'name': row.name,
            'value': row.value,
          },
        ),
    ];
  }

  Future<List<VaultRecord>> _tombstoneRecords() async {
    final rows = await _db.select(_db.vaultTombstones).get();
    return [
      for (final row in rows)
        VaultRecord(
          id: row.id,
          kind: VaultRecordKind.values.byName(row.kind),
          updatedAt: row.deletedAt.toUtc(),
          deviceId: row.deviceId,
          payload: const {},
          tombstone: true,
        ),
    ];
  }

  Future<void> _upsert(VaultRecord record) async {
    switch (record.kind) {
      case VaultRecordKind.host:
        await _upsertHost(record);
      case VaultRecordKind.snippet:
        await _hosts.upsertSnippet(
          Snippet(
            id: record.id,
            name: record.payload['name'] as String? ?? '',
            template: record.payload['template'] as String? ?? '',
            starter: record.payload['starter'] as bool? ?? false,
            hostId: record.payload['hostId'] as String?,
            tag: record.payload['tag'] as String?,
            startup: record.payload['startup'] as bool? ?? false,
          ),
        );
      case VaultRecordKind.hostTag:
        final hostId = record.payload['hostId'] as String? ?? '';
        final tag = record.payload['tag'] as String? ?? '';
        if (hostId.isEmpty || tag.isEmpty) {
          return;
        }
        await _db.into(_db.hostTags).insertOnConflictUpdate(
          HostTagsCompanion.insert(hostId: hostId, tag: tag),
        );
      case VaultRecordKind.hostKey:
        await _db.into(_db.hostKeys).insertOnConflictUpdate(
          HostKeysCompanion.insert(
            hostId: record.id,
            algorithm: record.payload['algorithm'] as String? ?? '',
            fingerprint: record.payload['fingerprint'] as String? ?? '',
            pinnedAt: record.updatedAt,
          ),
        );
      case VaultRecordKind.tunnel:
        await _tunnels.upsert(
          TunnelTarget(
            id: record.id,
            hostId: record.payload['hostId'] as String? ?? '',
            label: record.payload['label'] as String? ?? '',
            remoteHost: record.payload['remoteHost'] as String? ?? '127.0.0.1',
            remotePort: record.payload['remotePort'] as int? ?? 80,
            scheme: TunnelScheme.parse(record.payload['scheme'] as String? ?? '') ??
                TunnelScheme.http,
            path: record.payload['path'] as String? ?? '',
            kind: TunnelKind.parse(record.payload['kind'] as String? ?? ''),
          ),
        );
      case VaultRecordKind.pref:
        await _applyPrefs(record.payload);
      case VaultRecordKind.env:
        final name = record.payload['name'] as String? ?? '';
        if (!isEnvName(name)) {
          return;
        }
        await _hosts.upsertEnvBinding(
          EnvBinding(
            id: record.id,
            scope: EnvScope.values.byName(
              record.payload['scope'] as String? ?? EnvScope.host.name,
            ),
            scopeId: record.payload['scopeId'] as String? ?? '',
            name: name,
            value: record.payload['value'] as String? ?? '',
          ),
        );
      case VaultRecordKind.tombstone:
        break;
    }
  }

  Future<void> _upsertHost(VaultRecord record) async {
    final now = DateTime.now().toUtc();
    await _db.into(_db.hosts).insertOnConflictUpdate(
      HostsCompanion.insert(
        id: record.id,
        alias: record.payload['alias'] as String? ?? record.id,
        address: record.payload['address'] as String? ?? '',
        port: Value(record.payload['port'] as int? ?? 22),
        username: record.payload['username'] as String? ?? '',
        keyAlias: record.payload['keyAlias'] as String? ?? HostRepository.defaultKeyAlias,
        jumpHostId: Value(record.payload['jumpHostId'] as String?),
        readOnly: Value(record.payload['readOnly'] as bool? ?? false),
        note: Value(record.payload['note'] as String?),
        sortOrder: Value(record.payload['sortOrder'] as int? ?? 0),
        sudoNeedsPassword: Value(
          record.payload['sudoNeedsPassword'] as bool? ?? false,
        ),
        agentForward: Value(record.payload['agentForward'] as bool? ?? false),
        sshCertificate: Value(record.payload['sshCertificate'] as String?),
        createdAt: now,
        updatedAt: Value(record.updatedAt),
      ),
    );
  }

  Future<void> _applyPrefs(Map<String, Object?> payload) async {
    final row = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
      _hostsSettingsWrite(
        row,
        widgetEnabled: Value(payload['widgetEnabled'] as bool? ?? false),
        appLockTimeoutSec: Value(payload['appLockTimeoutSec'] as int? ?? 0),
        sessionLogRetentionDays: Value(
          payload['sessionLogRetentionDays'] as int? ?? 14,
        ),
        tunnelIdleMinutes: Value(payload['tunnelIdleMinutes'] as int? ?? 10),
        fleetWatchEnabled: Value(payload['fleetWatchEnabled'] as bool? ?? false),
      ),
    );
    final selected = payload['fleetSelection'];
    if (selected is List) {
      await (await _selectionOf()).write({
        for (final id in selected)
          if (id is String) id,
      });
    }
  }

  Future<void> _delete(VaultRecord record) async {
    final device = await deviceId();
    await _db.into(_db.vaultTombstones).insertOnConflictUpdate(
      VaultTombstonesCompanion.insert(
        id: record.id,
        kind: record.kind.name,
        deletedAt: record.updatedAt,
        deviceId: device,
      ),
    );
    switch (record.kind) {
      case VaultRecordKind.host:
        await _hosts.delete(record.id);
      case VaultRecordKind.snippet:
        await _hosts.deleteSnippet(record.id);
      case VaultRecordKind.hostTag:
        final parts = record.id.split('/');
        if (parts.length >= 2) {
          await (_db.delete(_db.hostTags)
                ..where((t) => t.hostId.equals(parts.first) & t.tag.equals(parts.sublist(1).join('/'))))
              .go();
        }
      case VaultRecordKind.hostKey:
        await (_db.delete(_db.hostKeys)..where((t) => t.hostId.equals(record.id)))
            .go();
      case VaultRecordKind.tunnel:
        await _tunnels.delete(record.id);
      case VaultRecordKind.env:
        await _hosts.deleteEnvBinding(record.id);
      case VaultRecordKind.pref:
      case VaultRecordKind.tombstone:
        break;
    }
  }

  Future<AppSettingsRow?> _settings() {
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
  }

  AppSettingsCompanion _hostsSettingsWrite(
    AppSettingsRow? existing, {
    Value<String?> deviceId = const Value.absent(),
    Value<bool> vaultIncludeSecrets = const Value.absent(),
    Value<bool> widgetEnabled = const Value.absent(),
    Value<int> appLockTimeoutSec = const Value.absent(),
    Value<int> sessionLogRetentionDays = const Value.absent(),
    Value<int> tunnelIdleMinutes = const Value.absent(),
    Value<bool> fleetWatchEnabled = const Value.absent(),
  }) {
    return AppSettingsCompanion(
      id: const Value(1),
      lastHostId: Value(existing?.lastHostId),
      publicKeySpkiB64: Value(existing?.publicKeySpkiB64),
      keyBackend: Value(existing?.keyBackend),
      widgetEnabled: widgetEnabled.present
          ? widgetEnabled
          : Value(existing?.widgetEnabled ?? false),
      llmProvider: Value(existing?.llmProvider ?? 'none'),
      llmBaseUrl: Value(existing?.llmBaseUrl),
      llmApiKey: const Value(null),
      llmModel: Value(existing?.llmModel),
      llmOllamaBaseUrl: Value(existing?.llmOllamaBaseUrl),
      llmOllamaModel: Value(existing?.llmOllamaModel),
      llmOpenaiBaseUrl: Value(existing?.llmOpenaiBaseUrl),
      llmOpenaiApiKey: const Value(null),
      llmOpenaiModel: Value(existing?.llmOpenaiModel),
      tunnelIdleMinutes: tunnelIdleMinutes.present
          ? tunnelIdleMinutes
          : Value(existing?.tunnelIdleMinutes ?? 10),
      snippetLibraryReady: Value(existing?.snippetLibraryReady ?? false),
      appLockTimeoutSec: appLockTimeoutSec.present
          ? appLockTimeoutSec
          : Value(existing?.appLockTimeoutSec ?? 0),
      sessionLogRetentionDays: sessionLogRetentionDays.present
          ? sessionLogRetentionDays
          : Value(existing?.sessionLogRetentionDays ?? 14),
      fleetWatchEnabled: fleetWatchEnabled.present
          ? fleetWatchEnabled
          : Value(existing?.fleetWatchEnabled ?? false),
      fleetWatchDiskPercent: Value(existing?.fleetWatchDiskPercent ?? 90),
      fleetWatchMemPercent: Value(existing?.fleetWatchMemPercent ?? 90),
      fleetWatchFailedUnits: Value(existing?.fleetWatchFailedUnits ?? 1),
      fleetWatchContainers: Value(existing?.fleetWatchContainers ?? 1),
      fleetWatchReboot: Value(existing?.fleetWatchReboot ?? true),
      fleetWatchLastTickAt: Value(existing?.fleetWatchLastTickAt),
      deviceId: deviceId.present ? deviceId : Value(existing?.deviceId),
      vaultIncludeSecrets: vaultIncludeSecrets.present
          ? vaultIncludeSecrets
          : Value(existing?.vaultIncludeSecrets ?? false),
    );
  }
}
