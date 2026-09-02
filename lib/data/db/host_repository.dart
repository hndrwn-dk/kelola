import 'package:drift/drift.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_edit.dart';
import 'package:kelola/domain/hosts/ssh_config_import.dart';
import 'package:uuid/uuid.dart';

class HostRepository {
  HostRepository(this._db);

  final KelolaDatabase _db;
  final _uuid = const Uuid();

  static const defaultKeyAlias = 'kelola-user';

  Future<List<Host>> list() async {
    final rows = await _db.select(_db.hosts).get();
    final facts = await _db.select(_db.cachedFacts).get();
    final byHost = {for (final f in facts) f.hostId: f};
    return rows
        .map((r) {
          final fact = byHost[r.id];
          return _toHost(
            r,
            prettyName: fact?.prettyName ?? fact?.osId,
            osId: fact?.osId,
          );
        })
        .toList();
  }

  Future<Host?> get(String id) async {
    final row = await (_db.select(_db.hosts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final fact = await (_db.select(_db.cachedFacts)
          ..where((t) => t.hostId.equals(id)))
        .getSingleOrNull();
    return _toHost(
      row,
      prettyName: fact?.prettyName ?? fact?.osId,
      osId: fact?.osId,
    );
  }

  Future<Host> insert({
    required String alias,
    required String address,
    required int port,
    required String username,
    String? jumpHostId,
    String? note,
    String keyAlias = defaultKeyAlias,
  }) async {
    final id = _uuid.v7();
    final now = DateTime.now().toUtc();
    await _db.into(_db.hosts).insert(
          HostsCompanion.insert(
            id: id,
            alias: alias,
            address: address,
            port: Value(port),
            username: username,
            keyAlias: keyAlias,
            jumpHostId: Value(jumpHostId),
            note: Value(note),
            createdAt: now,
          ),
        );
    return (await get(id))!;
  }

  Future<void> updateNote(String id, String? note) {
    return (_db.update(_db.hosts)..where((t) => t.id.equals(id))).write(
      HostsCompanion(note: Value(note)),
    );
  }

  Future<void> updateAttention({
    required String id,
    required HostAttention attention,
    int? rttMs,
    DateTime? lastSeenAt,
    int? failedUnitCount,
    int? diskRootPercent,
    DateTime? attentionAt,
  }) {
    return (_db.update(_db.hosts)..where((t) => t.id.equals(id))).write(
      HostsCompanion(
        attention: Value(attention.name),
        lastRttMs: rttMs != null ? Value(rttMs) : const Value.absent(),
        lastSeenAt:
            lastSeenAt != null ? Value(lastSeenAt) : const Value.absent(),
        failedUnitCount: failedUnitCount != null
            ? Value(failedUnitCount)
            : const Value.absent(),
        diskRootPercent: diskRootPercent != null
            ? Value(diskRootPercent)
            : const Value.absent(),
        attentionAt:
            attentionAt != null ? Value(attentionAt) : const Value.absent(),
      ),
    );
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.hosts)..where((t) => t.jumpHostId.equals(id)))
          .write(const HostsCompanion(jumpHostId: Value(null)));
      await (_db.delete(_db.hostKeys)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.cachedFacts)..where((t) => t.hostId.equals(id)))
          .go();
      await (_db.delete(_db.recents)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.pins)..where((t) => t.hostId.equals(id))).go();
      final last = await lastHostId();
      if (last == id) {
        await setLastHost(null);
      }
      await (_db.delete(_db.hosts)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<int> importSshConfig(String source) async {
    final imported = const SshConfigImporter().parse(source);
    final existing = await list();
    var created = 0;
    final byAlias = {for (final h in existing) h.alias: h};

    for (final item in imported) {
      if (byAlias.containsKey(item.alias)) {
        continue;
      }
      String? jumpId;
      if (item.proxyJump != null) {
        jumpId = byAlias[item.proxyJump!]?.id;
      }
      final host = await insert(
        alias: item.alias,
        address: item.address,
        port: item.port,
        username: item.username,
        jumpHostId: jumpId,
      );
      byAlias[host.alias] = host;
      created++;
    }
    return created;
  }

  Future<PinnedHostKey?> pinnedKey(String hostId) async {
    final row = await (_db.select(_db.hostKeys)
          ..where((t) => t.hostId.equals(hostId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return PinnedHostKey(
      algorithm: row.algorithm,
      fingerprint: row.fingerprint,
    );
  }

  Future<void> pinKey({
    required String hostId,
    required String algorithm,
    required String fingerprint,
  }) {
    return _db.into(_db.hostKeys).insertOnConflictUpdate(
          HostKeysCompanion.insert(
            hostId: hostId,
            algorithm: algorithm,
            fingerprint: fingerprint,
            pinnedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> saveFacts(String hostId, HostFacts facts) {
    return _db.into(_db.cachedFacts).insertOnConflictUpdate(
          CachedFactsCompanion.insert(
            hostId: hostId,
            osId: facts.osId,
            osVersionId: facts.osVersionId,
            prettyName: Value(facts.prettyName),
            initSystem: facts.init.name,
            systemdVersion: Value(facts.systemdVersion),
            pkg: facts.pkg.name,
            fw: facts.fw.name,
            hasJournald: facts.hasJournald,
            journalReadable: facts.journalReadable,
            arch: facts.arch,
            discoveredAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<HostFacts?> facts(String hostId) async {
    final row = await (_db.select(_db.cachedFacts)
          ..where((t) => t.hostId.equals(hostId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return HostFacts(
      osId: row.osId,
      osVersionId: row.osVersionId,
      prettyName: row.prettyName,
      init: InitSystem.values.byName(row.initSystem),
      systemdVersion: row.systemdVersion,
      pkg: PackageManager.values.byName(row.pkg),
      fw: FirewallBackend.values.byName(row.fw),
      hasJournald: row.hasJournald,
      journalReadable: row.journalReadable,
      arch: row.arch,
    );
  }

  Future<void> touchRecent(Host host) async {
    await _db.into(_db.recents).insert(
          RecentsCompanion.insert(
            kind: 'host',
            hostId: host.id,
            label: host.alias,
            viewedAt: DateTime.now().toUtc(),
          ),
        );
    final extras = await (_db.select(_db.recents)
          ..where((t) => t.kind.equals('host'))
          ..orderBy([(t) => OrderingTerm.desc(t.viewedAt)]))
        .get();
    if (extras.length > 10) {
      final drop = extras.sublist(10);
      await (_db.delete(_db.recents)
            ..where((t) => t.id.isIn(drop.map((e) => e.id))))
          .go();
    }
  }

  Future<void> setLastHost(String? id) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            lastHostId: Value(id),
          ),
        );
  }

  Future<String?> lastHostId() async {
    final row = await (_db.select(_db.appSettings)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    return row?.lastHostId;
  }

  Future<AppSettingsRow?> _settings() {
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
  }

  Future<void> saveDeviceKey({
    required String blobB64,
    required String backend,
  }) async {
    final existing = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            lastHostId: Value(existing?.lastHostId),
            publicKeySpkiB64: Value(blobB64),
            keyBackend: Value(backend),
          ),
        );
  }

  Future<({String blobB64, String? backend})?> loadDeviceKey() async {
    final row = await _settings();
    final blob = row?.publicKeySpkiB64;
    if (blob == null || blob.isEmpty) {
      return null;
    }
    return (blobB64: blob, backend: row?.keyBackend);
  }

  Future<void> clearDeviceKey() async {
    final existing = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            lastHostId: Value(existing?.lastHostId),
            publicKeySpkiB64: const Value(null),
            keyBackend: const Value(null),
          ),
        );
  }

  Future<void> setReadOnly(String id, bool value) async {
    await updateHost(id, readOnly: value);
  }

  /// Local mutate of host identity. Changing [address] deletes the pinned
  /// host key in the same transaction so the next connect must TOFU.
  Future<HostEditResult> updateHost(
    String id, {
    String? alias,
    String? address,
    int? port,
    String? username,
    String? jumpHostId,
    bool clearJumpHost = false,
    bool? readOnly,
  }) async {
    final current = await get(id);
    if (current == null) {
      throw StateError('Host $id missing');
    }

    final nextAlias = alias?.trim();
    final nextAddress = address?.trim();
    final nextUser = username?.trim();

    final aliasChanged =
        nextAlias != null && nextAlias.isNotEmpty && nextAlias != current.alias;
    final addressChanged = nextAddress != null &&
        nextAddress.isNotEmpty &&
        nextAddress != current.address;
    final portChanged = port != null && port != current.port;
    final userChanged =
        nextUser != null && nextUser.isNotEmpty && nextUser != current.username;
    final jumpChanged = clearJumpHost
        ? current.jumpHostId != null
        : jumpHostId != null && jumpHostId != current.jumpHostId;
    final roChanged = readOnly != null && readOnly != current.readOnly;

    if (!aliasChanged &&
        !addressChanged &&
        !portChanged &&
        !userChanged &&
        !jumpChanged &&
        !roChanged) {
      return const HostEditResult(pinReset: false, disconnectSession: false);
    }

    await _db.transaction(() async {
      await (_db.update(_db.hosts)..where((t) => t.id.equals(id))).write(
        HostsCompanion(
          alias: aliasChanged ? Value(nextAlias!) : const Value.absent(),
          address: addressChanged ? Value(nextAddress!) : const Value.absent(),
          port: portChanged ? Value(port!) : const Value.absent(),
          username: userChanged ? Value(nextUser!) : const Value.absent(),
          jumpHostId: clearJumpHost
              ? const Value(null)
              : (jumpChanged ? Value(jumpHostId) : const Value.absent()),
          readOnly: roChanged ? Value(readOnly!) : const Value.absent(),
        ),
      );
      if (addressChanged) {
        await (_db.delete(_db.hostKeys)..where((t) => t.hostId.equals(id)))
            .go();
      }
    });

    final hostAlias = aliasChanged ? nextAlias! : current.alias;
    final remoteUser = userChanged ? nextUser! : current.username;

    Future<void> audit(String title, String command) {
      return recordAudit(
        hostId: id,
        hostAlias: hostAlias,
        remoteUser: remoteUser,
        title: title,
        command: command,
        risk: 'mutate',
        usedSudo: false,
        exitCode: 0,
      );
    }

    if (aliasChanged) {
      await audit(HostEditAudit.renamed(nextAlias!), 'host-edit alias');
    }
    if (portChanged) {
      await audit(HostEditAudit.changedPort, 'host-edit port');
    }
    if (jumpChanged) {
      String? jumpAlias;
      if (!clearJumpHost && jumpHostId != null) {
        jumpAlias = (await get(jumpHostId))?.alias;
      }
      await audit(
        HostEditAudit.changedJump(clearJumpHost ? null : jumpAlias),
        'host-edit jump',
      );
    }
    if (userChanged) {
      await audit(HostEditAudit.changedUsername(nextUser!), 'host-edit username');
    }
    if (addressChanged) {
      await audit(HostEditAudit.changedAddress, 'host-edit address');
    }
    if (roChanged) {
      await audit(
        readOnly! ? HostEditAudit.setReadOnly : HostEditAudit.allowedWrites,
        'host-edit read-only',
      );
    }

    return HostEditResult(
      pinReset: addressChanged,
      disconnectSession:
          addressChanged || portChanged || userChanged || jumpChanged,
    );
  }

  Future<void> setSudoNeedsPassword(String id, bool value) {
    return (_db.update(_db.hosts)..where((t) => t.id.equals(id))).write(
      HostsCompanion(sudoNeedsPassword: Value(value)),
    );
  }

  Future<List<Host>> recentHosts() async {
    final rows = await (_db.select(_db.recents)
          ..where((t) => t.kind.equals('host'))
          ..orderBy([(t) => OrderingTerm.desc(t.viewedAt)])
          ..limit(20))
        .get();
    final seen = <String>{};
    final hosts = <Host>[];
    for (final row in rows) {
      if (!seen.add(row.hostId)) {
        continue;
      }
      final host = await get(row.hostId);
      if (host != null) {
        hosts.add(host);
      }
      if (hosts.length >= 10) {
        break;
      }
    }
    return hosts;
  }

  Future<String> beginAudit({
    required String hostId,
    required String hostAlias,
    required String remoteUser,
    required String command,
    required String risk,
    required bool usedSudo,
    String title = '',
  }) async {
    final id = _uuid.v7();
    await _db.into(_db.auditRecords).insert(
          AuditRecordsCompanion.insert(
            id: id,
            timestampUtc: DateTime.now().toUtc(),
            hostId: hostId,
            hostAlias: hostAlias,
            remoteUser: remoteUser,
            title: Value(title),
            command: command,
            risk: risk,
            usedSudo: usedSudo,
            appVersion: '0.1.0',
          ),
        );
    return id;
  }

  Future<void> finishAudit(
    String id, {
    int? exitCode,
    int durationMs = 0,
    String? errorSummary,
  }) {
    return (_db.update(_db.auditRecords)..where((t) => t.id.equals(id))).write(
      AuditRecordsCompanion(
        exitCode: Value(exitCode),
        durationMs: Value(durationMs),
        errorSummary: Value(errorSummary),
      ),
    );
  }

  Future<void> recordAudit({
    required String hostId,
    required String hostAlias,
    required String remoteUser,
    required String command,
    required String risk,
    required bool usedSudo,
    String title = '',
    int? exitCode,
    int durationMs = 0,
    String? errorSummary,
  }) {
    return _db.into(_db.auditRecords).insert(
          AuditRecordsCompanion.insert(
            id: _uuid.v7(),
            timestampUtc: DateTime.now().toUtc(),
            hostId: hostId,
            hostAlias: hostAlias,
            remoteUser: remoteUser,
            title: Value(title),
            command: command,
            risk: risk,
            usedSudo: usedSudo,
            exitCode: Value(exitCode),
            durationMs: Value(durationMs),
            errorSummary: Value(errorSummary),
            appVersion: '0.1.0',
          ),
        );
  }

  Future<List<AuditEvent>> listAudit({String? hostId, int limit = 200}) async {
    final query = _db.select(_db.auditRecords)
      ..orderBy([(t) => OrderingTerm.desc(t.timestampUtc)])
      ..limit(limit);
    if (hostId != null) {
      query.where((t) => t.hostId.equals(hostId));
    }
    final rows = await query.get();
    return rows
        .map(
          (row) => AuditEvent(
            id: row.id,
            timestampUtc: row.timestampUtc,
            hostId: row.hostId,
            hostAlias: row.hostAlias,
            remoteUser: row.remoteUser,
            title: row.title,
            command: row.command,
            risk: row.risk,
            usedSudo: row.usedSudo,
            durationMs: row.durationMs,
            appVersion: row.appVersion,
            exitCode: row.exitCode,
            errorSummary: row.errorSummary,
          ),
        )
        .toList();
  }

  Host _toHost(HostRow row, {String? prettyName, String? osId}) {
    return Host(
      id: row.id,
      alias: row.alias,
      address: row.address,
      port: row.port,
      username: row.username,
      keyAlias: row.keyAlias,
      jumpHostId: row.jumpHostId,
      readOnly: row.readOnly,
      sortOrder: row.sortOrder,
      note: row.note,
      lastRttMs: row.lastRttMs,
      attention: HostAttention.values.byName(row.attention),
      failedUnitCount: row.failedUnitCount,
      diskRootPercent: row.diskRootPercent,
      attentionAt: row.attentionAt,
      lastSeenAt: row.lastSeenAt,
      prettyName: prettyName,
      osId: osId,
      sudoNeedsPassword: row.sudoNeedsPassword,
    );
  }
}

class PinnedHostKey {
  const PinnedHostKey({required this.algorithm, required this.fingerprint});

  final String algorithm;
  final String fingerprint;
}
