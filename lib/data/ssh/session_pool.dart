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
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class SshSessionPool {
  SshSessionPool({
    required HostRepository repository,
    required HardwareSigner signer,
    required HostKeyPolicy hostKeys,
    required Uint8List Function() publicBlob,
    this.maxPerHost = 3,
  })  : _repository = repository,
        _signer = signer,
        _hostKeys = hostKeys,
        _publicBlob = publicBlob;

  final HostRepository _repository;
  final HardwareSigner _signer;
  final HostKeyPolicy _hostKeys;
  final Uint8List Function() _publicBlob;
  final int maxPerHost;

  final Map<String, List<SSHClient>> _pool = {};
  final ProbeAuditPolicy _auditPolicy = ProbeAuditPolicy();

  bool hasLiveSession(String hostId) {
    final list = _pool[hostId];
    return list != null && list.any((c) => !c.isClosed);
  }

  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
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
      final result = await client.runWithResult(command).timeout(probe.timeout);
      final parsed = probe.parse(
        utf8.decode(result.stdout),
        utf8.decode(result.stderr),
        result.exitCode ?? -1,
      );
      _auditPolicy.onSuccess(host.id);
      final durationMs = DateTime.now().difference(started).inMilliseconds;
      if (auditId != null) {
        await _repository.finishAudit(
          auditId,
          exitCode: result.exitCode,
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
          exitCode: result.exitCode,
          durationMs: durationMs,
        );
      }
      if (draft.usedSudo) {
        await _repository.setSudoNeedsPassword(host.id, false);
      }
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
    final list = _pool.remove(hostId) ?? [];
    for (final c in list) {
      await c.close();
    }
  }

  Future<void> closeAll() async {
    for (final id in _pool.keys.toList()) {
      await disconnect(id);
    }
  }
}
