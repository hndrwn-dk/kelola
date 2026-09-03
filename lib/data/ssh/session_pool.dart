import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/hardware_identity.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/kelola_algorithms.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/audit/probe_audit_policy.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/data/ssh/dart_sftp_port.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/search/search_index_write.dart';
import 'package:kelola/domain/incident/correlation.dart';

typedef JournalFollowOpener = Future<JournalFollowChannel> Function({
  required Host host,
  required String command,
  UnknownHostKeyHandler? onUnknownHostKey,
});

class SshSessionPool {
  SshSessionPool({
    required HostRepository repository,
    required HardwareSigner signer,
    required HostKeyPolicy hostKeys,
    required Uint8List Function() publicBlob,
    this.maxPerHost = 3,
    JournalFollowOpener? followOpener,
    CorrelationStore? correlation,
  })  : _repository = repository,
        _signer = signer,
        _hostKeys = hostKeys,
        _publicBlob = publicBlob,
        _followOpener = followOpener,
        _correlation = correlation ?? CorrelationStore();

  final HostRepository _repository;
  final HardwareSigner _signer;
  final HostKeyPolicy _hostKeys;
  final Uint8List Function() _publicBlob;
  final int maxPerHost;
  final JournalFollowOpener? _followOpener;
  final CorrelationStore _correlation;

  final Map<String, List<SSHClient>> _pool = {};
  final Map<String, SSHClient> _followClients = {};
  final Map<String, JournalFollowHandle> _follows = {};
  final ProbeAuditPolicy _auditPolicy = ProbeAuditPolicy();

  bool hasLiveSession(String hostId) {
    final list = _pool[hostId];
    if (list != null && list.any((c) => !c.isClosed)) {
      return true;
    }
    final follow = _followClients[hostId];
    return follow != null && !follow.isClosed;
  }

  int get activeFollowCount =>
      _follows.values.where((h) => h.isOpen).length;

  bool hasActiveFollow(String hostId) {
    final handle = _follows[hostId];
    return handle != null && handle.isOpen;
  }

  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
  }) async {
    if (host.username == 'root') {
      throw RootLoginRejectedException();
    }
    final resolvedFacts = facts ?? HostFacts.undiscovered;
    final draft = AuditDraft.fromProbe(probe, resolvedFacts);
    if (host.readOnly && probe.risk != RiskLevel.read) {
      await _repository.recordAudit(
        hostId: host.id,
        hostAlias: host.alias,
        remoteUser: host.username,
        title: draft.title,
        command: draft.command,
        risk: draft.risk,
        usedSudo: draft.usedSudo,
        errorSummary: 'ReadOnlyViolation',
      );
      throw ReadOnlyViolation(probe);
    }
    final command = draft.command;
    final started = DateTime.now();
    final skipProbeAudit = _auditPolicy.alreadyLost(host.id);
    String? auditId;
    if (!skipProbeAudit) {
      auditId = await _repository.beginAudit(
        hostId: host.id,
        hostAlias: host.alias,
        remoteUser: host.username,
        title: draft.title,
        command: draft.command,
        risk: draft.risk,
        usedSudo: draft.usedSudo,
      );
    }
    try {
      final client = await _acquire(host, onUnknownHostKey: onUnknownHostKey);
      late final T parsed;
      int? exitCode = 0;
      if (probe is SftpProbe<T>) {
        final sftp = await client.sftp();
        try {
          final future = probe.run(
            DartSshSftpPort(sftp),
            onProgress: onProgress,
            cancel: cancel,
          );
          parsed = probe.isStream
              ? await future
              : await future.timeout(probe.timeout);
        } finally {
          await sftp.close();
        }
      } else {
        final result = await client.runWithResult(command).timeout(probe.timeout);
        exitCode = result.exitCode;
        parsed = probe.parse(
          utf8.decode(result.stdout),
          utf8.decode(result.stderr),
          result.exitCode ?? -1,
        );
      }
      _auditPolicy.onSuccess(host.id);
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      if (auditId != null) {
        await _repository.finishAudit(
          auditId,
          exitCode: exitCode,
          durationMs: durationMs,
        );
      } else {
        await _repository.recordAudit(
          hostId: host.id,
          hostAlias: host.alias,
          remoteUser: host.username,
          title: draft.title,
          command: draft.command,
          risk: draft.risk,
          usedSudo: draft.usedSudo,
          exitCode: exitCode,
          durationMs: durationMs,
        );
      }
      if (draft.usedSudo) {
        await _repository.setSudoNeedsPassword(host.id, false);
      }
      await writeSearchIndexFromProbe(
        repo: _repository,
        hostId: host.id,
        parsed: parsed,
      );
      _correlation.ingest(host.id, probe, parsed);
      return parsed;
    } catch (e) {
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      final title = _auditPolicy.titleOnFailure(
        hostId: host.id,
        probeTitle: draft.title,
        error: e,
      );
      if (title != null) {
        if (auditId != null) {
          await _repository.finishAudit(
            auditId,
            durationMs: durationMs,
            errorSummary: e.runtimeType.toString(),
            title: title == connectionLostTitle ? connectionLostTitle : title,
          );
        } else {
          await _repository.recordAudit(
            hostId: host.id,
            hostAlias: host.alias,
            remoteUser: host.username,
            title: title,
            command: draft.command,
            risk: draft.risk,
            usedSudo: draft.usedSudo,
            durationMs: durationMs,
            errorSummary: e.runtimeType.toString(),
          );
        }
      }
      if (e is SudoRequiredException) {
        await _repository.setSudoNeedsPassword(host.id, true);
      }
      if (e is HostKeyMismatchException) {
        rethrow;
      }
      if (e is SSHAuthAbortError || e is SSHHostkeyError) {
        final mismatch = _hostKeys.takeMismatch();
        if (mismatch != null) {
          throw mismatch;
        }
        throw SshUnavailableException(describeSshError(e));
      }
      rethrow;
    }
  }

  Future<JournalFollowHandle> startJournalFollow(
    Host host, {
    required HostFacts facts,
    required void Function(JournalEntry entry) onEntry,
    String? unit,
    int? priority,
    String? grep,
    void Function()? onDenied,
    void Function(Object error)? onError,
    void Function()? onClosed,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    await stopJournalFollow(host.id);
    final command = JournalFollowCommand(
      unit: unit,
      priority: priority,
      grep: grep,
    ).command(facts);
    final opener = _followOpener ?? _openFollowChannel;
    final channel = await opener(
      host: host,
      command: command,
      onUnknownHostKey: onUnknownHostKey,
    );
    final handle = JournalFollowHandle.bind(
      channel: channel,
      onEntry: onEntry,
      onDenied: onDenied,
      onError: onError,
      onClosed: onClosed,
    );
    _follows[host.id] = handle;
    return handle;
  }

  Future<void> stopJournalFollow(String hostId) async {
    final handle = _follows.remove(hostId);
    await handle?.cancel();
  }

  Future<JournalFollowChannel> _openFollowChannel({
    required Host host,
    required String command,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    final stale = _followClients.remove(host.id);
    if (stale != null && !stale.isClosed) {
      await stale.close();
    }
    _pool[host.id]?.removeWhere((c) => c.isClosed);
    final used = _pool[host.id]?.length ?? 0;
    if (used >= maxPerHost) {
      await _pool[host.id]!.removeLast().close();
    }
    final client = await _open(
      host,
      {host.id},
      onUnknownHostKey: onUnknownHostKey,
    );
    _followClients[host.id] = client;
    final session = await client.execute(
      command,
      pty: journalFollowRequiresPty ? const SSHPtyConfig() : null,
    );
    return _DartSshFollowChannel(
      client: client,
      session: session,
      onClosed: () => _followClients.remove(host.id),
    );
  }

  Future<SSHClient> _acquire(
    Host host, {
    Set<String>? visiting,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    visiting ??= <String>{};
    if (!visiting.add(host.id)) {
      throw SshUnavailableException('Jump host cycle involving ${host.alias}');
    }

    _pool[host.id]?.removeWhere((c) => c.isClosed);
    final existing = _pool[host.id];
    if (existing != null && existing.isNotEmpty) {
      return existing.first;
    }

    final client = await _open(
      host,
      visiting,
      onUnknownHostKey: onUnknownHostKey,
    );
    final list = _pool.putIfAbsent(host.id, () => []);
    if (list.length >= maxPerHost) {
      await list.removeLast().close();
    }
    list.insert(0, client);
    return client;
  }

  Future<SSHClient> _open(
    Host host,
    Set<String> visiting, {
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    SSHSocket socket;
    if (host.jumpHostId != null) {
      final jump = await _repository.get(host.jumpHostId!);
      if (jump == null) {
        throw SshUnavailableException('Jump host missing for ${host.alias}');
      }
      final jumpClient = await _acquire(
        jump,
        visiting: visiting,
        onUnknownHostKey: onUnknownHostKey,
      );
      socket = await jumpClient.forwardLocal(host.address, host.port);
    } else {
      socket = await SSHSocket.connect(
        host.address,
        host.port,
        timeout: const Duration(seconds: 12),
      );
    }

    final identity = HardwareSshIdentity(
      signer: _signer,
      alias: host.keyAlias,
      publicBlob: _publicBlob(),
    ).toIdentity();

    final client = SSHClient(
      socket,
      username: host.username,
      identities: [identity],
      algorithms: KelolaAlgorithms.ssh,
      keepAliveInterval: const Duration(seconds: 30),
      onVerifyHostKey: (type, fingerprint) {
        return _hostKeys.verify(
          hostId: host.id,
          algorithm: type,
          fingerprintBytes: fingerprint,
          onUnknown: onUnknownHostKey == null
              ? null
              : (algorithm, fp) => onUnknownHostKey(host.id, algorithm, fp),
        );
      },
    );
    try {
      // Must outlast the TOFU prompt. dartssh2 holds NEWKEYS until verify
      // returns; a 20s cap made first connect look like issue #83.
      await client.authenticated.timeout(const Duration(minutes: 2));
      return client;
    } catch (_) {
      await client.close();
      rethrow;
    }
  }

  Future<void> disconnect(String hostId) async {
    await stopJournalFollow(hostId);
    final follow = _followClients.remove(hostId);
    if (follow != null && !follow.isClosed) {
      await follow.close();
    }
    final list = _pool.remove(hostId) ?? [];
    for (final c in list) {
      await c.close();
    }
  }

  Future<void> closeAll() async {
    final ids = {..._pool.keys, ..._followClients.keys, ..._follows.keys};
    for (final id in ids) {
      await disconnect(id);
    }
  }
}

class _DartSshFollowChannel implements JournalFollowChannel {
  _DartSshFollowChannel({
    required SSHClient client,
    required SSHSession session,
    required this.onClosed,
  })  : _client = client,
        _session = session {
    // Drain stderr so a full stderr window cannot stall stdout.
    _stderrSub = _session.stderr.listen((_) {}, onError: (_) {});
  }

  final SSHClient _client;
  final SSHSession _session;
  final void Function() onClosed;
  StreamSubscription<List<int>>? _stderrSub;
  bool _closed = false;

  @override
  Stream<List<int>> get stdout => _session.stdout;

  @override
  bool get isClosed => _closed || _client.isClosed;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _stderrSub?.cancel();
    _stderrSub = null;
    try {
      _session.kill(SSHSignal.TERM);
    } catch (_) {}
    _session.close();
    if (!_client.isClosed) {
      await _client.close();
    }
    onClosed();
  }
}
