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
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/data/ssh/dart_sftp_port.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/domain/probes/key_install_append_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/sftp_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/search/search_index_write.dart';
import 'package:kelola/domain/incident/correlation.dart';

typedef JournalFollowOpener = Future<JournalFollowChannel> Function({
  required Host host,
  required String command,
  UnknownHostKeyHandler? onUnknownHostKey,
});

/// Password handler that yields material only after host-key verify accepts.
///
/// dartssh2 may invoke [SSHClient.onPasswordRequest] around auth; gate so the
/// password is never returned until TOFU/mismatch handling completes.
FutureOr<String?> Function() gatedPasswordRequest({
  required Completer<bool> hostKeyAccepted,
  required FutureOr<String?> Function() onPasswordRequest,
}) {
  return () async {
    if (!await hostKeyAccepted.future) {
      return null;
    }
    return await onPasswordRequest();
  };
}

/// Parses dartssh2 [printTrace] lines for `SSH_Message_Userauth_Failure`.
///
/// dartssh2 does not expose `methodsLeft` on [SSHAuthFailError]; the failure
/// message is only visible on the partial-auth trace path. Returns null when
/// the line is not a userauth failure.
Set<String>? parseUserauthFailureMethodsLeft(String trace) {
  final match = RegExp(
    r'SSH_Message_Userauth_Failure\(methodsLeft:\s*\[(.*?)\]',
  ).firstMatch(trace);
  if (match == null) {
    return null;
  }
  final inner = match.group(1)!.trim();
  if (inner.isEmpty) {
    return <String>{};
  }
  return inner
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toSet();
}

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
  /// Dedicated key-only SSH clients for tunnels (one per host). Not exec `_pool`.
  final Map<String, SSHClient> _tunnelClients = {};
  final Map<String, JournalFollowHandle> _follows = {};
  final ProbeAuditPolicy _auditPolicy = ProbeAuditPolicy();

  /// Optional seam: tear down active tunnels before SSH clients disconnect.
  ///
  /// Wired by providers so [closeAll] also runs [TunnelManager.closeAll].
  Future<void> Function()? closeTunnels;

  /// True when the most recent client open used password auth.
  /// Cleared at the start of every open via [noteClientOpen].
  bool lastOpenUsedPassword = false;

  /// Whether host-key verify accepted for the latest password bootstrap open.
  /// Reset to false when a password open begins; set from verify.
  bool lastHostKeyAccepted = false;

  /// True when the user declined an unknown host key (TOFU cancel) during the
  /// latest password bootstrap open. Distinct from never reaching verify.
  bool lastHostKeyDeclined = false;

  /// Last `methodsLeft` captured from dartssh2 userauth failure traces for the
  /// latest password bootstrap attempt. Empty until a failure message arrives.
  Set<String> lastServerAuthMethods = {};

  /// Records whether the upcoming client construction used password.
  /// Overridable in tests; production sets [lastOpenUsedPassword].
  void noteClientOpen({required bool usedPassword}) {
    lastOpenUsedPassword = usedPassword;
    if (usedPassword) {
      lastHostKeyAccepted = false;
      lastHostKeyDeclined = false;
      lastServerAuthMethods = {};
    }
  }

  /// Hook for dartssh2 [SSHClient.printTrace] during bootstrap auth.
  void considerAuthTrace(String? message) {
    if (message == null) {
      return;
    }
    final methods = parseUserauthFailureMethodsLeft(message);
    if (methods != null) {
      lastServerAuthMethods = methods;
    }
  }

  bool hasLiveSession(String hostId) {
    final list = _pool[hostId];
    if (list != null && list.any((c) => !c.isClosed)) {
      return true;
    }
    final follow = _followClients[hostId];
    if (follow != null && !follow.isClosed) {
      return true;
    }
    final tunnel = _tunnelClients[hostId];
    return tunnel != null && !tunnel.isClosed;
  }

  /// Test hook: clients currently held in the key-auth pool for [hostId].
  /// Bootstrap open must leave this at 0.
  int debugPooledCount(String hostId) => _pool[hostId]?.length ?? 0;

  /// Test hook: dedicated tunnel clients held for [hostId] (0 or 1).
  int debugTunnelClientCount(String hostId) {
    final client = _tunnelClients[hostId];
    if (client == null || client.isClosed) {
      return 0;
    }
    return 1;
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
    ProbeScope scope = ProbeScope.host,
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
    // Successful Fleet-scope reads must not flood Insights (spec B).
    final quietFleetRead =
        scope == ProbeScope.fleet && probe.risk == RiskLevel.read;
    String? auditId;
    if (!skipProbeAudit && !quietFleetRead) {
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
        if (probe is JournalProbe) {
          logJournalProbeReceive(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
          );
        }
        parsed = probe.parse(
          utf8.decode(result.stdout, allowMalformed: true),
          utf8.decode(result.stderr, allowMalformed: true),
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
      } else if (!quietFleetRead && !skipProbeAudit) {
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
    JournalScope scope = JournalScope.all,
    void Function()? onDenied,
    void Function(JournalAccess? learnedAccess)? onNoSyslog,
    void Function(Object error)? onError,
    void Function()? onClosed,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    await stopJournalFollow(host.id);
    final command = JournalFollowCommand(
      unit: unit,
      priority: priority,
      grep: grep,
      scope: scope,
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
      onNoSyslog: onNoSyslog,
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
    final client = await openSession(
      host,
      visiting: {host.id},
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

  /// Dedicated key-only SSH client for tunnels on [host].
  ///
  /// Separate from the exec [_pool] so long-lived forwards do not consume
  /// probe slots. Uses [openSession] → [createAndAuthenticateClient] (30s
  /// keepalive). Never password bootstrap.
  Future<SSHClient> acquireTunnelClient(
    Host host, {
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    final existing = _tunnelClients[host.id];
    if (existing != null && !existing.isClosed) {
      return existing;
    }
    if (existing != null) {
      _tunnelClients.remove(host.id);
    }
    final client = await openSession(
      host,
      visiting: {host.id},
      onUnknownHostKey: onUnknownHostKey,
    );
    _tunnelClients[host.id] = client;
    return client;
  }

  /// Closes and drops the dedicated tunnel client for [hostId], if any.
  ///
  /// Call when the last tunnel for that host is gone so idle SSH sessions
  /// do not linger after idle/user/fail teardown.
  Future<void> releaseTunnelClient(String hostId) async {
    final tunnel = _tunnelClients.remove(hostId);
    if (tunnel != null && !tunnel.isClosed) {
      await tunnel.close();
    }
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

    final client = await openSession(
      host,
      visiting: visiting,
      onUnknownHostKey: onUnknownHostKey,
    );
    final list = _pool.putIfAbsent(host.id, () => []);
    if (list.length >= maxPerHost) {
      await list.removeLast().close();
    }
    list.insert(0, client);
    return client;
  }

  /// Opens a TCP/jump socket for [host]. Override in tests to avoid real SSH.
  Future<SSHSocket> connectSocket(
    Host host,
    Set<String> visiting, {
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
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
      return jumpClient.forwardLocal(host.address, host.port);
    }
    return SSHSocket.connect(
      host.address,
      host.port,
      timeout: const Duration(seconds: 12),
    );
  }

  /// Opens an SSH client. Normal pool / execute paths must omit
  /// [onPasswordRequest] (key identity only). Password bootstrap is the sole
  /// caller that passes a password handler — and must not insert the client
  /// into [_pool].
  ///
  /// Fresh verify after bootstrap: [disconnect] then [execute] (or
  /// [verifyFreshKeyAuth]) so a new key-only client is acquired.
  Future<SSHClient> openSession(
    Host host, {
    Set<String>? visiting,
    UnknownHostKeyHandler? onUnknownHostKey,
    FutureOr<String?> Function()? onPasswordRequest,
  }) async {
    visiting ??= <String>{host.id};
    final usePassword = onPasswordRequest != null;
    // Record before connect so tests can inspect password vs key-only without
    // completing a real handshake.
    noteClientOpen(usedPassword: usePassword);

    final socket = await connectSocket(
      host,
      visiting,
      onUnknownHostKey: onUnknownHostKey,
    );

    final hostKeyGate = Completer<bool>();

    Future<bool> verifyHostKey(String type, Uint8List fingerprint) async {
      final accepted = await _hostKeys.verify(
        hostId: host.id,
        algorithm: type,
        fingerprintBytes: fingerprint,
        onUnknown: onUnknownHostKey == null
            ? null
            : (algorithm, fp) async {
                final ok = await onUnknownHostKey(host.id, algorithm, fp);
                if (usePassword && !ok) {
                  lastHostKeyDeclined = true;
                }
                return ok;
              },
      );
      if (usePassword) {
        lastHostKeyAccepted = accepted;
        if (!hostKeyGate.isCompleted) {
          hostKeyGate.complete(accepted);
        }
      }
      return accepted;
    }

    // Password bootstrap: no key identities (avoids hardware presence prompts
    // while the key is not yet authorized). Key-only opens keep identities and
    // never set onPasswordRequest.
    final List<SSHIdentity>? identities = usePassword
        ? null
        : [
            HardwareSshIdentity(
              signer: _signer,
              alias: host.keyAlias,
              publicBlob: _publicBlob(),
            ).toIdentity(),
          ];

    final passwordRequest = onPasswordRequest;
    final FutureOr<String?> Function()? passwordHandler = passwordRequest == null
        ? null
        : gatedPasswordRequest(
            hostKeyAccepted: hostKeyGate,
            onPasswordRequest: passwordRequest,
          );

    try {
      return await createAndAuthenticateClient(
        socket: socket,
        username: host.username,
        identities: identities,
        onVerifyHostKey: verifyHostKey,
        onPasswordRequest: passwordHandler,
      );
    } catch (e) {
      // Mirror execute: changed pins must surface HostKeyMismatchException so
      // enrollment mismatch UI runs (not TOFU for an unknown key).
      if (e is HostKeyMismatchException) {
        rethrow;
      }
      if (e is SSHAuthAbortError || e is SSHHostkeyError) {
        final mismatch = _hostKeys.takeMismatch();
        if (mismatch != null) {
          throw mismatch;
        }
      }
      rethrow;
    }
  }

  /// Builds the SSH client and awaits authentication.
  ///
  /// Override in tests to drive host-key / password handlers without a real
  /// handshake. Production path closes the client before rethrowing.
  Future<SSHClient> createAndAuthenticateClient({
    required SSHSocket socket,
    required String username,
    required List<SSHIdentity>? identities,
    required Future<bool> Function(String type, Uint8List fingerprint)
        onVerifyHostKey,
    FutureOr<String?> Function()? onPasswordRequest,
  }) async {
    final client = SSHClient(
      socket,
      username: username,
      identities: identities,
      algorithms: KelolaAlgorithms.ssh,
      keepAliveInterval: const Duration(seconds: 30),
      onVerifyHostKey: onVerifyHostKey,
      onPasswordRequest: onPasswordRequest,
      // dartssh2 only surfaces methodsLeft on Userauth_Failure traces, not on
      // SSHAuthFailError — capture them for password-bootstrap classification.
      printTrace: onPasswordRequest == null ? null : considerAuthTrace,
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

  /// Appends [fullLine] via [KeyInstallAppendProbe] on an authenticated client.
  ///
  /// Overridable in tests so UI flows can assert verify/mismatch without SSH.
  Future<KeyInstallAppendResult> appendAuthorizedKeysLine({
    required SSHClient client,
    required String keyBody,
    required String fullLine,
  }) async {
    final install = KeyInstallAppendProbe(keyBody: keyBody, fullLine: fullLine);
    final command = install.command(HostFacts.undiscovered);
    final result = await client.runWithResult(command).timeout(install.timeout);
    return install.parse(
      utf8.decode(result.stdout, allowMalformed: true),
      utf8.decode(result.stderr, allowMalformed: true),
      result.exitCode ?? -1,
    );
  }

  /// Password-only bootstrap open. Client is **not** inserted into the pool —
  /// callers must close it and must not treat it as proof of key auth.
  Future<SSHClient> openPasswordBootstrap(
    Host host, {
    required FutureOr<String?> Function() onPasswordRequest,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) {
    return openSession(
      host,
      visiting: {host.id},
      onUnknownHostKey: onUnknownHostKey,
      onPasswordRequest: onPasswordRequest,
    );
  }

  /// Runs [body] on a non-pooled password bootstrap client, then closes it
  /// and [disconnect]s so verify cannot reuse the bootstrap session.
  ///
  /// After this returns, call [verifyFreshKeyAuth] (or [disconnect] then
  /// key-only [execute]) for STEP 5 verify — never reuse the bootstrap client.
  Future<T> runPasswordBootstrap<T>({
    required Host host,
    required EphemeralPassword password,
    required UnknownHostKeyHandler onUnknownHostKey,
    required Future<T> Function(SSHClient client) body,
  }) async {
    SSHClient? client;
    try {
      client = await openPasswordBootstrap(
        host,
        onUnknownHostKey: onUnknownHostKey,
        // openSession gates password behind host-key accept; pass read only.
        onPasswordRequest: () => password.read(),
      );
      return await body(client);
    } finally {
      if (client != null && !client.isClosed) {
        await client.close();
      }
      await disconnect(host.id);
    }
  }

  /// Fresh key-only proof after password bootstrap.
  ///
  /// Disconnects [host.id] first so any leftover pooled/bootstrap session
  /// cannot satisfy verify, then [execute]s with key identity only.
  Future<T> verifyFreshKeyAuth<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    await disconnect(host.id);
    return execute(
      host,
      probe,
      facts: facts,
      onUnknownHostKey: onUnknownHostKey,
    );
  }

  Future<void> disconnect(String hostId) async {
    await stopJournalFollow(hostId);
    final follow = _followClients.remove(hostId);
    if (follow != null && !follow.isClosed) {
      await follow.close();
    }
    final tunnel = _tunnelClients.remove(hostId);
    if (tunnel != null && !tunnel.isClosed) {
      await tunnel.close();
    }
    final list = _pool.remove(hostId) ?? [];
    for (final c in list) {
      await c.close();
    }
  }

  Future<void> closeAll() async {
    final closer = closeTunnels;
    if (closer != null) {
      await closer();
    }
    final ids = {
      ..._pool.keys,
      ..._followClients.keys,
      ..._tunnelClients.keys,
      ..._follows.keys,
    };
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
