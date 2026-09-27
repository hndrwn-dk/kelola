import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/command_history/command_history.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_edit.dart';
import 'package:kelola/domain/hosts/ssh_config_import.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/domain/journal/journal_bookmark.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/session_logs/session_log.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/snippet_scope.dart';
import 'package:kelola/domain/snippets/starters.dart';
import 'package:kelola/data/secrets/secret_store.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/app_version.dart';
import 'package:uuid/uuid.dart';

class HostRepository {
  HostRepository(this._db, {SecretStore? secrets})
      : _secrets = secrets ?? MemorySecretStore();

  final KelolaDatabase _db;
  final SecretStore _secrets;
  final _uuid = const Uuid();

  static const defaultKeyAlias = 'kelola-user';

  Future<List<Host>> list() async {
    final rows = await _db.select(_db.hosts).get();
    final facts = await _db.select(_db.cachedFacts).get();
    final tags = await _db.select(_db.hostTags).get();
    return _hostsFromRows(rows, facts, tags);
  }

  /// Live membership + attention. Re-emits when hosts, facts, or tags change.
  Stream<List<Host>> watchList() async* {
    yield await list();
    yield* _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.hosts,
            _db.cachedFacts,
            _db.hostTags,
          ]),
        )
        .asyncMap((_) => list());
  }

  List<Host> _hostsFromRows(
    List<HostRow> rows,
    List<CachedFactsRow> facts,
    List<HostTagRow> tags,
  ) {
    final byHost = {for (final f in facts) f.hostId: f};
    final tagsByHost = <String, List<String>>{};
    for (final t in tags) {
      tagsByHost.putIfAbsent(t.hostId, () => []).add(t.tag);
    }
    for (final list in tagsByHost.values) {
      list.sort();
    }
    return rows.map((r) {
      final fact = byHost[r.id];
      return _toHost(
        r,
        prettyName: fact?.prettyName ?? fact?.osId,
        osId: fact?.osId,
        tags: tagsByHost[r.id] ?? const [],
      );
    }).toList();
  }

  Future<Host?> get(String id) async {
    final row = await (_db.select(
      _db.hosts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    final fact = await (_db.select(
      _db.cachedFacts,
    )..where((t) => t.hostId.equals(id))).getSingleOrNull();
    final tags = await (_db.select(
      _db.hostTags,
    )..where((t) => t.hostId.equals(id))).get();
    final tagList = tags.map((t) => t.tag).toList()..sort();
    return _toHost(
      row,
      prettyName: fact?.prettyName ?? fact?.osId,
      osId: fact?.osId,
      tags: tagList,
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
    await _db
        .into(_db.hosts)
        .insert(
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
            updatedAt: Value(now),
          ),
        );
    return (await get(id))!;
  }

  Future<void> updateNote(String id, String? note) {
    return (_db.update(
      _db.hosts,
    )..where((t) => t.id.equals(id))).write(HostsCompanion(note: Value(note)));
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
        lastSeenAt: lastSeenAt != null
            ? Value(lastSeenAt)
            : const Value.absent(),
        failedUnitCount: failedUnitCount != null
            ? Value(failedUnitCount)
            : const Value.absent(),
        diskRootPercent: diskRootPercent != null
            ? Value(diskRootPercent)
            : const Value.absent(),
        attentionAt: attentionAt != null
            ? Value(attentionAt)
            : const Value.absent(),
      ),
    );
  }

  Future<void> delete(String id) async {
    await _db.transaction(() async {
      await (_db.update(_db.hosts)..where((t) => t.jumpHostId.equals(id)))
          .write(const HostsCompanion(jumpHostId: Value(null)));
      await (_db.delete(_db.hostKeys)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.cachedFacts,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.searchIndexCache,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.hostTags)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.fleetCache,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.tunnelTargets,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.recents)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.commandHistory,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.sessionLogs,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.journalBookmarks,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(
        _db.fleetWatchState,
      )..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.snippets)..where((t) => t.hostId.equals(id))).go();
      await (_db.delete(_db.pins)..where((t) => t.hostId.equals(id))).go();
      final last = await lastHostId();
      if (last == id) {
        await setLastHost(null);
      }
      final settings = await _settings();
      final device = settings?.deviceId ?? _uuid.v7();
      if (settings?.deviceId == null || settings!.deviceId!.isEmpty) {
        await _db.into(_db.appSettings).insertOnConflictUpdate(
          _appSettingsWrite(settings, deviceId: Value(device)),
        );
      }
      await _db.into(_db.vaultTombstones).insertOnConflictUpdate(
        VaultTombstonesCompanion.insert(
          id: id,
          kind: 'host',
          deletedAt: DateTime.now().toUtc(),
          deviceId: device,
        ),
      );
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
    final row = await (_db.select(
      _db.hostKeys,
    )..where((t) => t.hostId.equals(hostId))).getSingleOrNull();
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
    return _db
        .into(_db.hostKeys)
        .insertOnConflictUpdate(
          HostKeysCompanion.insert(
            hostId: hostId,
            algorithm: algorithm,
            fingerprint: fingerprint,
            pinnedAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> saveFacts(String hostId, HostFacts facts) async {
    final previous = await this.facts(hostId);
    final merged = coalesceJournalAccess(facts, previous);
    await _db
        .into(_db.cachedFacts)
        .insertOnConflictUpdate(
          CachedFactsCompanion.insert(
            hostId: hostId,
            osId: merged.osId,
            osVersionId: merged.osVersionId,
            prettyName: Value(merged.prettyName),
            initSystem: merged.init.name,
            systemdVersion: Value(merged.systemdVersion),
            pkg: merged.pkg.name,
            fw: merged.fw.name,
            hasJournald: merged.hasJournald,
            journalReadable: merged.journalReadable,
            journalAccess: Value(merged.journalAccess.name),
            arch: merged.arch,
            discoveredAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<HostFacts?> facts(String hostId) async {
    final row = await (_db.select(
      _db.cachedFacts,
    )..where((t) => t.hostId.equals(hostId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    final access =
        JournalAccess.values.asNameMap()[row.journalAccess] ??
        (row.journalReadable ? JournalAccess.plain : JournalAccess.unknown);
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
      journalAccess: access,
      arch: row.arch,
    );
  }

  Future<void> touchRecent(Host host) async {
    await _db
        .into(_db.recents)
        .insert(
          RecentsCompanion.insert(
            kind: 'host',
            hostId: host.id,
            label: host.alias,
            viewedAt: DateTime.now().toUtc(),
          ),
        );
    final extras =
        await (_db.select(_db.recents)
              ..where((t) => t.kind.equals('host'))
              ..orderBy([(t) => OrderingTerm.desc(t.viewedAt)]))
            .get();
    if (extras.length > 10) {
      final drop = extras.sublist(10);
      await (_db.delete(
        _db.recents,
      )..where((t) => t.id.isIn(drop.map((e) => e.id)))).go();
    }
  }

  Future<void> recordCommandHistory(
    String hostId,
    String command, {
    DateTime? now,
  }) async {
    if (!shouldRecordCommandHistory(command)) {
      return;
    }
    final line = normalizeCommandHistoryLine(command);
    final usedAt = now ?? DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db
          .into(_db.commandHistory)
          .insertOnConflictUpdate(
            CommandHistoryCompanion.insert(
              hostId: hostId,
              command: line,
              usedAt: usedAt,
            ),
          );
      final extras =
          await (_db.select(_db.commandHistory)
                ..where((t) => t.hostId.equals(hostId))
                ..orderBy([(t) => OrderingTerm.desc(t.usedAt)]))
              .get();
      if (extras.length <= kCommandHistoryCap) {
        return;
      }
      final drop = extras.sublist(kCommandHistoryCap);
      for (final row in drop) {
        await (_db.delete(_db.commandHistory)..where(
              (t) =>
                  t.hostId.equals(row.hostId) & t.command.equals(row.command),
            ))
            .go();
      }
    });
  }

  Future<List<String>> listCommandHistory(
    String hostId, {
    String query = '',
  }) async {
    final rows =
        await (_db.select(_db.commandHistory)
              ..where((t) => t.hostId.equals(hostId))
              ..orderBy([(t) => OrderingTerm.desc(t.usedAt)]))
            .get();
    return filterCommandHistory(rows.map((r) => r.command).toList(), query);
  }

  Future<String?> recordSessionLog(
    String hostId, {
    required String title,
    required String body,
    DateTime? now,
    bool bookmarked = false,
  }) async {
    if (!shouldRecordSessionLog(title)) {
      return null;
    }
    final createdAt = now ?? DateTime.now().toUtc();
    final id = _uuid.v7();
    await _db
        .into(_db.sessionLogs)
        .insert(
          SessionLogsCompanion.insert(
            id: id,
            hostId: hostId,
            title: title.trim(),
            body: clipSessionLogBody(body),
            createdAt: createdAt,
            bookmarked: Value(bookmarked),
          ),
        );
    await _pruneSessionLogs(hostId, now: createdAt);
    return id;
  }

  Future<List<SessionLog>> listSessionLogs(
    String hostId, {
    String query = '',
    DateTime? now,
  }) async {
    await _pruneSessionLogs(hostId, now: now ?? DateTime.now().toUtc());
    return filterSessionLogs(await _sessionLogsForHost(hostId), query);
  }

  Future<void> setSessionLogBookmarked(String id, bool value) async {
    await (_db.update(_db.sessionLogs)..where((t) => t.id.equals(id))).write(
      SessionLogsCompanion(bookmarked: Value(value)),
    );
  }

  Future<int> sessionLogRetentionDays() async {
    final raw =
        (await _settings())?.sessionLogRetentionDays ??
        kDefaultSessionLogRetentionDays;
    return SessionLogRetention.fromDays(raw).days;
  }

  Future<void> setSessionLogRetentionDays(int days) async {
    final existing = await _settings();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
            sessionLogRetentionDays: Value(
              SessionLogRetention.fromDays(days).days,
            ),
          ),
        );
  }

  Future<List<SessionLog>> _sessionLogsForHost(String hostId) async {
    final rows = await (_db.select(
      _db.sessionLogs,
    )..where((t) => t.hostId.equals(hostId))).get();
    final logs = rows.map(_toSessionLog).toList();
    logs.sort((a, b) {
      if (a.bookmarked != b.bookmarked) {
        return a.bookmarked ? -1 : 1;
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return logs;
  }

  Future<void> _pruneSessionLogs(
    String hostId, {
    required DateTime now,
  }) async {
    final current = await _sessionLogsForHost(hostId);
    final kept = pruneSessionLogs(
      logs: current,
      now: now,
      retentionDays: await sessionLogRetentionDays(),
    );
    final keepIds = kept.map((l) => l.id).toSet();
    for (final log in current) {
      if (keepIds.contains(log.id)) {
        continue;
      }
      await (_db.delete(_db.sessionLogs)..where((t) => t.id.equals(log.id)))
          .go();
    }
  }

  SessionLog _toSessionLog(SessionLogRow row) {
    return SessionLog(
      id: row.id,
      hostId: row.hostId,
      kind: row.kind,
      title: row.title,
      body: row.body,
      createdAt: row.createdAt,
      bookmarked: row.bookmarked,
    );
  }

  Future<JournalBookmark> saveJournalBookmark({
    required String hostId,
    String? unit,
    required String query,
    required JournalScope scope,
    int? priority,
    bool lastHour = false,
    DateTime? now,
  }) async {
    final createdAt = now ?? DateTime.now().toUtc();
    final label = journalBookmarkLabel(
      unit: unit,
      query: query,
      scope: scope,
      priority: priority,
      lastHour: lastHour,
    );
    final incoming = JournalBookmark(
      id: 'tmp',
      hostId: hostId,
      label: label,
      unit: unit,
      query: query.trim(),
      scope: scope,
      priority: priority,
      lastHour: lastHour,
      createdAt: createdAt,
    );
    final existing = await listJournalBookmarks(hostId);
    for (final row in existing) {
      if (sameJournalBookmark(row, incoming)) {
        return row;
      }
    }
    final id = _uuid.v7();
    await _db
        .into(_db.journalBookmarks)
        .insert(
          JournalBookmarksCompanion.insert(
            id: id,
            hostId: hostId,
            label: label,
            unit: Value(unit),
            query: Value(query.trim()),
            scope: Value(scope.name),
            priority: Value(priority),
            lastHour: Value(lastHour),
            createdAt: createdAt,
          ),
        );
    final all = await listJournalBookmarks(hostId);
    if (all.length > kJournalBookmarkCap) {
      for (final extra in all.sublist(kJournalBookmarkCap)) {
        await deleteJournalBookmark(extra.id);
      }
    }
    return JournalBookmark(
      id: id,
      hostId: hostId,
      label: label,
      unit: unit,
      query: query.trim(),
      scope: scope,
      priority: priority,
      lastHour: lastHour,
      createdAt: createdAt,
    );
  }

  Future<List<JournalBookmark>> listJournalBookmarks(String hostId) async {
    final rows =
        await (_db.select(_db.journalBookmarks)
              ..where((t) => t.hostId.equals(hostId))
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows.map(_toJournalBookmark).toList();
  }

  Future<void> deleteJournalBookmark(String id) async {
    await (_db.delete(_db.journalBookmarks)..where((t) => t.id.equals(id))).go();
  }

  JournalBookmark _toJournalBookmark(JournalBookmarkRow row) {
    return JournalBookmark(
      id: row.id,
      hostId: row.hostId,
      label: row.label,
      unit: row.unit,
      query: row.query,
      scope: journalScopeFromName(row.scope),
      priority: row.priority,
      lastHour: row.lastHour,
      createdAt: row.createdAt,
    );
  }

  Future<void> setLastHost(String? id) async {
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(id: const Value(1), lastHostId: Value(id)),
        );
  }

  Future<String?> lastHostId() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    return row?.lastHostId;
  }

  Stream<String?> watchLastHostId() {
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1)))
        .watchSingleOrNull()
        .map((row) => row?.lastHostId);
  }

  Future<AppSettingsRow?> _settings() async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    if (row.llmOpenaiApiKey == null && row.llmApiKey == null) {
      return row;
    }
    await _openaiApiKey(row);
    return (_db.select(_db.appSettings)..where((t) => t.id.equals(1)))
        .getSingleOrNull();
  }

  Future<void> saveDeviceKey({
    required String blobB64,
    required String backend,
  }) async {
    final existing = await _settings();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
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
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
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
    final addressChanged =
        nextAddress != null &&
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
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      if (addressChanged) {
        await (_db.delete(
          _db.hostKeys,
        )..where((t) => t.hostId.equals(id))).go();
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
      await audit(
        HostEditAudit.changedUsername(nextUser!),
        'host-edit username',
      );
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
    final rows =
        await (_db.select(_db.recents)
              ..where((t) => t.kind.equals('host'))
              ..orderBy([(t) => OrderingTerm.desc(t.viewedAt)])
              ..limit(20))
            .get();
    return _hostsFromRecentRows(rows);
  }

  Stream<List<Host>> watchRecentHosts() async* {
    yield await recentHosts();
    yield* _db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            _db.recents,
            _db.hosts,
            _db.cachedFacts,
            _db.hostTags,
          ]),
        )
        .asyncMap((_) => recentHosts());
  }

  Future<List<Host>> _hostsFromRecentRows(List<RecentRow> rows) async {
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
    String? closeReason,
  }) async {
    final id = _uuid.v7();
    await _db
        .into(_db.auditRecords)
        .insert(
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
            closeReason: Value(closeReason),
            appVersion: kelolaAppVersion,
          ),
        );
    return id;
  }

  Future<void> finishAudit(
    String id, {
    int? exitCode,
    int durationMs = 0,
    String? errorSummary,
    String? title,
    String? closeReason,
  }) {
    return (_db.update(_db.auditRecords)..where((t) => t.id.equals(id))).write(
      AuditRecordsCompanion(
        exitCode: Value(exitCode),
        durationMs: Value(durationMs),
        errorSummary: Value(errorSummary),
        title: title == null ? const Value.absent() : Value(title),
        closeReason: closeReason == null
            ? const Value.absent()
            : Value(closeReason),
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
    String? closeReason,
  }) {
    return _db
        .into(_db.auditRecords)
        .insert(
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
            closeReason: Value(closeReason),
            appVersion: kelolaAppVersion,
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
    return rows.map(_auditFromRow).toList();
  }

  /// Insights / week summary: full 7-day window, not newest-N.
  Future<List<AuditEvent>> listAuditSince(
    DateTime sinceUtc, {
    String? hostId,
  }) async {
    final since = sinceUtc.toUtc();
    final query = _db.select(_db.auditRecords)
      ..where((t) => t.timestampUtc.isBiggerOrEqualValue(since))
      ..orderBy([(t) => OrderingTerm.desc(t.timestampUtc)]);
    if (hostId != null) {
      query.where((t) => t.hostId.equals(hostId));
    }
    final rows = await query.get();
    return rows.map(_auditFromRow).toList();
  }

  AuditEvent _auditFromRow(AuditRow row) {
    return AuditEvent(
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
      closeReason: row.closeReason,
    );
  }

  static const searchKindUnit = 'unit';
  static const searchKindContainer = 'container';
  static const searchKindFailedUnit = 'failed_unit';

  Future<void> replaceSearchUnits({
    required String hostId,
    required List<String> names,
    required DateTime at,
  }) {
    return _replaceSearchKind(
      hostId: hostId,
      kind: searchKindUnit,
      names: names,
      at: at,
    );
  }

  Future<void> replaceSearchFailedUnits({
    required String hostId,
    required List<String> names,
    required DateTime at,
  }) {
    return _replaceSearchKind(
      hostId: hostId,
      kind: searchKindFailedUnit,
      names: names,
      at: at,
    );
  }

  Future<void> replaceSearchContainers({
    required String hostId,
    required List<String> names,
    required DateTime at,
  }) {
    return _replaceSearchKind(
      hostId: hostId,
      kind: searchKindContainer,
      names: names,
      at: at,
    );
  }

  Future<List<String>> listFailedUnitNames(String hostId) async {
    final rows =
        await (_db.select(_db.searchIndexCache)..where(
              (t) =>
                  t.hostId.equals(hostId) & t.kind.equals(searchKindFailedUnit),
            ))
            .get();
    return [for (final r in rows) r.name];
  }

  Future<void> _replaceSearchKind({
    required String hostId,
    required String kind,
    required List<String> names,
    required DateTime at,
  }) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.searchIndexCache,
      )..where((t) => t.hostId.equals(hostId) & t.kind.equals(kind))).go();
      final seen = <String>{};
      for (final raw in names) {
        final name = raw.trim();
        if (name.isEmpty || !seen.add(name)) {
          continue;
        }
        await _db
            .into(_db.searchIndexCache)
            .insert(
              SearchIndexCacheCompanion.insert(
                hostId: hostId,
                kind: kind,
                name: name,
                indexedAt: at.toUtc(),
              ),
            );
      }
    });
  }

  Future<List<SearchUnit>> listSearchUnits() async {
    final aliases = await _hostAliases();
    final rows = await (_db.select(
      _db.searchIndexCache,
    )..where((t) => t.kind.equals(searchKindUnit))).get();
    return rows
        .map(
          (row) => SearchUnit(
            hostId: row.hostId,
            hostAlias: aliases[row.hostId] ?? row.hostId,
            unit: ServiceUnit(
              name: row.name,
              description: '',
              load: '',
              active: '',
              sub: '',
            ),
            indexedAt: row.indexedAt,
          ),
        )
        .toList();
  }

  Future<List<SearchContainer>> listSearchContainers() async {
    final aliases = await _hostAliases();
    final rows = await (_db.select(
      _db.searchIndexCache,
    )..where((t) => t.kind.equals(searchKindContainer))).get();
    return rows
        .map(
          (row) => SearchContainer(
            hostId: row.hostId,
            hostAlias: aliases[row.hostId] ?? row.hostId,
            row: ContainerRow(
              id: row.name,
              names: row.name,
              image: '',
              state: '',
              status: '',
            ),
            indexedAt: row.indexedAt,
          ),
        )
        .toList();
  }

  Future<Map<String, String>> _hostAliases() async {
    final rows = await _db.select(_db.hosts).get();
    return {for (final r in rows) r.id: r.alias};
  }

  Host _toHost(
    HostRow row, {
    String? prettyName,
    String? osId,
    List<String> tags = const [],
  }) {
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
      tags: tags,
    );
  }

  Future<void> setHostTags(String hostId, List<String> tags) async {
    final cleaned =
        tags
            .map((t) => t.trim().toLowerCase())
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    await _db.transaction(() async {
      await (_db.delete(
        _db.hostTags,
      )..where((t) => t.hostId.equals(hostId))).go();
      for (final tag in cleaned) {
        await _db
            .into(_db.hostTags)
            .insert(HostTagsCompanion.insert(hostId: hostId, tag: tag));
      }
    });
  }

  Future<List<String>> listAllTags() async {
    final rows = await _db.select(_db.hostTags).get();
    final set = rows.map((r) => r.tag).toSet().toList()..sort();
    return set;
  }

  Future<void> saveFleetCache(FleetHostHealth health) async {
    await _db
        .into(_db.fleetCache)
        .insertOnConflictUpdate(
          FleetCacheCompanion.insert(
            hostId: health.hostId,
            reachable: health.reachable,
            load1: health.load1,
            diskRootPercent: health.diskRootPercent ?? -1,
            failedUnitCount: health.failedUnitCount,
            pendingUpdates: health.pendingUpdates,
            fetchedAt: health.fetchedAt.toUtc(),
            nprocCores: Value(health.nprocCores),
            memPercent: Value(health.memPercent),
            highDiskJson: Value(jsonEncode(health.highDiskMounts)),
            securityUpdates: Value(health.securityUpdates),
            containersDown: Value(health.containersDown),
            containersUnhealthy: Value(health.containersUnhealthy),
            uptimeSeconds: Value(health.uptime?.inSeconds ?? -1),
            rebootRequired: Value(health.rebootRequired),
          ),
        );
  }

  Future<Map<String, FleetHostHealth>> loadFleetCacheByHost() async {
    final rows = await _db.select(_db.fleetCache).get();
    final hosts = await _db.select(_db.hosts).get();
    final aliasById = {for (final h in hosts) h.id: h.alias};
    return {
      for (final r in rows)
        r.hostId: FleetHostHealth(
          hostId: r.hostId,
          alias: aliasById[r.hostId] ?? r.hostId,
          reachable: r.reachable,
          load1: r.load1,
          nprocCores: r.nprocCores,
          memPercent: r.memPercent,
          diskRootPercent: r.diskRootPercent < 0 ? null : r.diskRootPercent,
          highDiskMounts: _decodeStringList(r.highDiskJson),
          failedUnitCount: r.failedUnitCount,
          pendingUpdates: r.pendingUpdates,
          securityUpdates: r.securityUpdates,
          containersDown: r.containersDown,
          containersUnhealthy: r.containersUnhealthy,
          uptime: r.uptimeSeconds < 0
              ? null
              : Duration(seconds: r.uptimeSeconds),
          rebootRequired: r.rebootRequired,
          fetchedAt: r.fetchedAt,
          fromCache: true,
        ),
    };
  }

  List<String> _decodeStringList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => '$e').toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> widgetEnabled() async {
    return (await _settings())?.widgetEnabled ?? false;
  }

  Future<void> setWidgetEnabled(bool value) async {
    final existing = await _settings();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(existing, widgetEnabled: Value(value)),
        );
  }

  Future<int> appLockTimeoutSec() async {
    return (await _settings())?.appLockTimeoutSec ?? 0;
  }

  Future<bool> fleetWatchEnabled() async {
    return (await _settings())?.fleetWatchEnabled ?? false;
  }

  Future<void> setFleetWatchEnabled(bool value) async {
    final existing = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          _appSettingsWrite(existing, fleetWatchEnabled: Value(value)),
        );
  }

  Future<FleetWatchThresholds> fleetWatchThresholds() async {
    final row = await _settings();
    return FleetWatchThresholds(
      diskPercent: _clampWatchPercent(row?.fleetWatchDiskPercent ?? 90),
      memPercent: _clampWatchPercent(row?.fleetWatchMemPercent ?? 90),
      failedUnits: _clampWatchCount(row?.fleetWatchFailedUnits ?? 1),
      containers: _clampWatchCount(row?.fleetWatchContainers ?? 1),
      reboot: row?.fleetWatchReboot ?? true,
    );
  }

  Future<void> setFleetWatchThresholds(FleetWatchThresholds value) async {
    final existing = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
            fleetWatchDiskPercent: Value(_clampWatchPercent(value.diskPercent)),
            fleetWatchMemPercent: Value(_clampWatchPercent(value.memPercent)),
            fleetWatchFailedUnits: Value(_clampWatchCount(value.failedUnits)),
            fleetWatchContainers: Value(_clampWatchCount(value.containers)),
            fleetWatchReboot: Value(value.reboot),
          ),
        );
  }

  Future<DateTime?> fleetWatchLastTickAt() async {
    return (await _settings())?.fleetWatchLastTickAt;
  }

  Future<void> setFleetWatchLastTickAt(DateTime value) async {
    final existing = await _settings();
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
            fleetWatchLastTickAt: Value(value.toUtc()),
          ),
        );
  }

  Future<String?> fleetWatchFingerprint(String hostId) async {
    final row = await (_db.select(_db.fleetWatchState)
          ..where((t) => t.hostId.equals(hostId)))
        .getSingleOrNull();
    return row?.fingerprint;
  }

  Future<void> setFleetWatchFingerprint(String hostId, String fingerprint) {
    return _db.into(_db.fleetWatchState).insertOnConflictUpdate(
          FleetWatchStateCompanion.insert(
            hostId: hostId,
            fingerprint: fingerprint,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  static int _clampWatchPercent(int value) {
    if (value < 50) return 50;
    if (value > 99) return 99;
    return value;
  }

  static int _clampWatchCount(int value) {
    if (value < 1) return 1;
    if (value > 20) return 20;
    return value;
  }

  Future<void> setAppLockTimeoutSec(int value) async {
    final existing = await _settings();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(existing, appLockTimeoutSec: Value(value)),
        );
  }

  Future<LlmSettings> loadLlmSettings() async {
    return (await loadLlmSettingsBundle()).resolved;
  }

  Future<LlmSettingsBundle> loadLlmSettingsBundle() async {
    final row = await _settings();
    return LlmSettingsBundle(
      activeProvider: LlmProvider.parse(row?.llmProvider),
      ollama: LlmEndpointConfig(
        baseUrl: row?.llmOllamaBaseUrl,
        model: row?.llmOllamaModel,
      ),
      openaiCompatible: LlmEndpointConfig(
        baseUrl: row?.llmOpenaiBaseUrl,
        apiKey: await _openaiApiKey(row),
        model: row?.llmOpenaiModel,
      ),
    );
  }

  Future<void> saveLlmSettings(LlmSettings settings) async {
    // Legacy single-slot API: write into the active provider's slot only.
    final existing = await loadLlmSettingsBundle();
    final draft = LlmEndpointConfig(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
    );
    await saveLlmSettingsBundle(
      existing.persistEdit(
        draftProvider: settings.provider,
        draftConfig: draft,
      ),
    );
  }

  Future<void> saveLlmSettingsBundle(LlmSettingsBundle bundle) async {
    final key = bundle.openaiCompatible.apiKey?.trim() ?? '';
    if (key.isEmpty) {
      await _secrets.delete(kLlmOpenaiApiKeySecret);
    } else {
      await _secrets.write(kLlmOpenaiApiKeySecret, key);
    }
    final existing = await _settings();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(
            existing,
            llmProvider: Value(bundle.activeProvider.storageName),
            llmOllamaBaseUrl: Value(bundle.ollama.baseUrl),
            llmOllamaModel: Value(bundle.ollama.model),
            llmOpenaiBaseUrl: Value(bundle.openaiCompatible.baseUrl),
            llmOpenaiModel: Value(bundle.openaiCompatible.model),
          ),
        );
    await _wipeSqliteApiKeys();
  }

  Future<String?> _openaiApiKey(AppSettingsRow? row) async {
    final stored = await _secrets.read(kLlmOpenaiApiKeySecret);
    if (stored != null && stored.isNotEmpty) {
      if (row?.llmOpenaiApiKey != null || row?.llmApiKey != null) {
        await _wipeSqliteApiKeys();
      }
      return stored;
    }
    final leftover = row?.llmOpenaiApiKey ?? row?.llmApiKey;
    if (leftover == null || leftover.isEmpty) {
      return null;
    }
    await _secrets.write(kLlmOpenaiApiKeySecret, leftover);
    await _wipeSqliteApiKeys();
    return leftover;
  }

  Future<void> _wipeSqliteApiKeys() async {
    await (_db.update(_db.appSettings)..where((t) => t.id.equals(1))).write(
      const AppSettingsCompanion(
        llmOpenaiApiKey: Value(null),
        llmApiKey: Value(null),
      ),
    );
  }

  /// Upsert app_settings row 1, preserving any field not explicitly overridden.
  AppSettingsCompanion _appSettingsWrite(
    AppSettingsRow? existing, {
    Value<String?> lastHostId = const Value.absent(),
    Value<String?> publicKeySpkiB64 = const Value.absent(),
    Value<String?> keyBackend = const Value.absent(),
    Value<bool> widgetEnabled = const Value.absent(),
    Value<String> llmProvider = const Value.absent(),
    Value<String?> llmOllamaBaseUrl = const Value.absent(),
    Value<String?> llmOllamaModel = const Value.absent(),
    Value<String?> llmOpenaiBaseUrl = const Value.absent(),
    Value<String?> llmOpenaiModel = const Value.absent(),
    Value<int> tunnelIdleMinutes = const Value.absent(),
    Value<bool> snippetLibraryReady = const Value.absent(),
    Value<int> appLockTimeoutSec = const Value.absent(),
    Value<int> sessionLogRetentionDays = const Value.absent(),
    Value<bool> fleetWatchEnabled = const Value.absent(),
    Value<int> fleetWatchDiskPercent = const Value.absent(),
    Value<int> fleetWatchMemPercent = const Value.absent(),
    Value<int> fleetWatchFailedUnits = const Value.absent(),
    Value<int> fleetWatchContainers = const Value.absent(),
    Value<bool> fleetWatchReboot = const Value.absent(),
    Value<DateTime?> fleetWatchLastTickAt = const Value.absent(),
    Value<String?> deviceId = const Value.absent(),
    Value<bool> vaultIncludeSecrets = const Value.absent(),
  }) {
    return AppSettingsCompanion(
      id: const Value(1),
      lastHostId: lastHostId.present ? lastHostId : Value(existing?.lastHostId),
      publicKeySpkiB64: publicKeySpkiB64.present
          ? publicKeySpkiB64
          : Value(existing?.publicKeySpkiB64),
      keyBackend: keyBackend.present ? keyBackend : Value(existing?.keyBackend),
      widgetEnabled: widgetEnabled.present
          ? widgetEnabled
          : Value(existing?.widgetEnabled ?? false),
      llmProvider: llmProvider.present
          ? llmProvider
          : Value(existing?.llmProvider ?? 'none'),
      // Legacy shared columns: preserve only; new writes go to per-provider cols.
      // API keys never go back to SQLite — they live in SecretStore.
      llmBaseUrl: Value(existing?.llmBaseUrl),
      llmApiKey: const Value(null),
      llmModel: Value(existing?.llmModel),
      llmOllamaBaseUrl: llmOllamaBaseUrl.present
          ? llmOllamaBaseUrl
          : Value(existing?.llmOllamaBaseUrl),
      llmOllamaModel: llmOllamaModel.present
          ? llmOllamaModel
          : Value(existing?.llmOllamaModel),
      llmOpenaiBaseUrl: llmOpenaiBaseUrl.present
          ? llmOpenaiBaseUrl
          : Value(existing?.llmOpenaiBaseUrl),
      llmOpenaiApiKey: const Value(null),
      llmOpenaiModel: llmOpenaiModel.present
          ? llmOpenaiModel
          : Value(existing?.llmOpenaiModel),
      tunnelIdleMinutes: tunnelIdleMinutes.present
          ? tunnelIdleMinutes
          : Value(existing?.tunnelIdleMinutes ?? 10),
      snippetLibraryReady: snippetLibraryReady.present
          ? snippetLibraryReady
          : Value(existing?.snippetLibraryReady ?? false),
      appLockTimeoutSec: appLockTimeoutSec.present
          ? appLockTimeoutSec
          : Value(existing?.appLockTimeoutSec ?? 0),
      sessionLogRetentionDays: sessionLogRetentionDays.present
          ? sessionLogRetentionDays
          : Value(
              existing?.sessionLogRetentionDays ??
                  kDefaultSessionLogRetentionDays,
            ),
      fleetWatchEnabled: fleetWatchEnabled.present
          ? fleetWatchEnabled
          : Value(existing?.fleetWatchEnabled ?? false),
      fleetWatchDiskPercent: fleetWatchDiskPercent.present
          ? fleetWatchDiskPercent
          : Value(existing?.fleetWatchDiskPercent ?? 90),
      fleetWatchMemPercent: fleetWatchMemPercent.present
          ? fleetWatchMemPercent
          : Value(existing?.fleetWatchMemPercent ?? 90),
      fleetWatchFailedUnits: fleetWatchFailedUnits.present
          ? fleetWatchFailedUnits
          : Value(existing?.fleetWatchFailedUnits ?? 1),
      fleetWatchContainers: fleetWatchContainers.present
          ? fleetWatchContainers
          : Value(existing?.fleetWatchContainers ?? 1),
      fleetWatchReboot: fleetWatchReboot.present
          ? fleetWatchReboot
          : Value(existing?.fleetWatchReboot ?? true),
      fleetWatchLastTickAt: fleetWatchLastTickAt.present
          ? fleetWatchLastTickAt
          : Value(existing?.fleetWatchLastTickAt),
      deviceId: deviceId.present ? deviceId : Value(existing?.deviceId),
      vaultIncludeSecrets: vaultIncludeSecrets.present
          ? vaultIncludeSecrets
          : Value(existing?.vaultIncludeSecrets ?? false),
    );
  }

  Future<List<Snippet>> listSnippets() async {
    final settings = await _settingsRow();
    if (settings == null || !settings.snippetLibraryReady) {
      await seedShippedSnippets();
      await _markSnippetLibraryReady();
    }
    final rows = await _db.select(_db.snippets).get();
    return rows.map(_toSnippet).toList();
  }

  Future<List<Snippet>> listSnippetsForHost(Host host) async {
    final all = await listSnippets();
    return snippetsForHost(all, host);
  }

  /// Inserts shipped starters that are missing. Never updates an existing
  /// row, so an edited starter stays user-owned.
  Future<int> restoreStarterSnippets() async {
    final existing = await _db.select(_db.snippets).get();
    final ids = existing.map((row) => row.id).toSet();
    var added = 0;
    final now = DateTime.now().toUtc();
    for (final starter in shippedSnippets) {
      if (ids.contains(starter.id)) {
        continue;
      }
      await _db
          .into(_db.snippets)
          .insert(
            SnippetsCompanion(
              id: Value(starter.id),
              name: Value(starter.name),
              template: Value(starter.template),
              starter: const Value(true),
              updatedAt: Value(now),
              hostId: Value(starter.hostId),
              tag: Value(starter.tag),
              startup: Value(starter.startup),
            ),
          );
      added++;
    }
    await _markSnippetLibraryReady();
    return added;
  }

  Future<AppSettingsRow?> _settingsRow() {
    return (_db.select(
      _db.appSettings,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
  }

  Future<void> _markSnippetLibraryReady() async {
    final existing = await _settingsRow();
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          _appSettingsWrite(existing, snippetLibraryReady: const Value(true)),
        );
  }

  Future<void> seedShippedSnippets() async {
    final now = DateTime.now().toUtc();
    for (final s in shippedSnippets) {
      await _db
          .into(_db.snippets)
          .insertOnConflictUpdate(
            SnippetsCompanion(
              id: Value(s.id),
              name: Value(s.name),
              template: Value(s.template),
              starter: Value(s.starter),
              updatedAt: Value(now),
              hostId: Value(s.hostId),
              tag: Value(s.tag),
              startup: Value(s.startup),
            ),
          );
    }
  }

  Future<void> upsertSnippet(Snippet snippet) {
    return _db
        .into(_db.snippets)
        .insertOnConflictUpdate(
          SnippetsCompanion(
            id: Value(snippet.id),
            name: Value(snippet.name),
            template: Value(snippet.template),
            starter: Value(snippet.starter),
            updatedAt: Value(DateTime.now().toUtc()),
            hostId: Value(snippet.hostId),
            tag: Value(snippet.tag),
            startup: Value(snippet.startup),
          ),
        );
  }

  Future<void> deleteSnippet(String id) {
    return (_db.delete(_db.snippets)..where((t) => t.id.equals(id))).go();
  }

  Snippet _toSnippet(SnippetRow row) {
    return Snippet(
      id: row.id,
      name: row.name,
      template: row.template,
      starter: row.starter,
      hostId: row.hostId,
      tag: row.tag,
      startup: row.startup,
    );
  }
}

class PinnedHostKey {
  const PinnedHostKey({required this.algorithm, required this.fingerprint});

  final String algorithm;
  final String fingerprint;
}
