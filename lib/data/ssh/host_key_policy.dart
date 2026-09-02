import 'dart:convert';
import 'dart:typed_data';

import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/exceptions.dart';

/// Called while the server waits for NEWKEYS. Must not throw.
typedef UnknownHostKeyHandler = Future<bool> Function(
  String hostId,
  String algorithm,
  String fingerprint,
);

typedef UnknownHostKeyDecision = Future<bool> Function(
  String algorithm,
  String fingerprint,
);

class HostKeyPolicy {
  HostKeyPolicy(this._repo);

  final HostRepository _repo;
  HostKeyMismatchException? _lastMismatch;

  HostKeyMismatchException? takeMismatch() {
    final mismatch = _lastMismatch;
    _lastMismatch = null;
    return mismatch;
  }

  /// Must not throw. dartssh2 awaits this while the server waits for NEWKEYS.
  /// Throwing aborts the handshake and surfaces as SSHAuthAbortError (#83).
  Future<bool> verify({
    required String hostId,
    required String algorithm,
    required Uint8List fingerprintBytes,
    UnknownHostKeyDecision? onUnknown,
  }) async {
    _lastMismatch = null;
    final seen = utf8.decode(fingerprintBytes);
    final pinned = await _repo.pinnedKey(hostId);
    if (pinned == null) {
      if (onUnknown == null) {
        return false;
      }
      return onUnknown(algorithm, seen);
    }
    if (pinned.fingerprint != seen || pinned.algorithm != algorithm) {
      await _repo.recordAudit(
        hostId: hostId,
        hostAlias: hostId,
        remoteUser: '',
        title: 'Host key mismatch',
        command: 'host-key-verify',
        risk: 'read',
        usedSudo: false,
        exitCode: 1,
        errorSummary: 'host key mismatch $seen',
      );
      _lastMismatch = HostKeyMismatchException(
        hostId: hostId,
        pinnedFingerprint: pinned.fingerprint,
        seenFingerprint: seen,
        algorithm: algorithm,
      );
      return false;
    }
    return true;
  }
}
