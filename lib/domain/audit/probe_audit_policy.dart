import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/domain/exceptions.dart';

const connectionLostTitle = 'Connection lost';

bool isSshConnectionFailure(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is SshUnavailableException ||
      error is SSHAuthAbortError ||
      error is SSHDisconnectError) {
    return true;
  }
  return false;
}

/// One "Connection lost" audit row per disconnect, not one per poll.
class ProbeAuditPolicy {
  final _lost = <String>{};

  bool alreadyLost(String hostId) => _lost.contains(hostId);

  void onSuccess(String hostId) => _lost.remove(hostId);

  /// Title to persist after a failed execute, or null to skip writing.
  String? titleOnFailure({
    required String hostId,
    required String probeTitle,
    required Object error,
  }) {
    if (!isSshConnectionFailure(error)) {
      return probeTitle;
    }
    if (_lost.contains(hostId)) {
      return null;
    }
    _lost.add(hostId);
    return connectionLostTitle;
  }
}
