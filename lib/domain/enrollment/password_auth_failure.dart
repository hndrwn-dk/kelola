import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

enum PasswordAuthFailureMode {
  rejected,
  passwordDisabled,
  connectionFailed,
  hostKeyDeclined,
}

class PasswordAuthFailure {
  const PasswordAuthFailure({
    required this.mode,
    required this.message,
    required this.offerRetry,
  });

  final PasswordAuthFailureMode mode;
  final String message;
  final bool offerRetry;
}

PasswordAuthFailure classifyPasswordAuthFailure({
  required Object error,
  required bool hostKeyVerified,
  required bool passwordMethodOffered,
  bool hostKeyDeclined = false,
}) {
  if (hostKeyDeclined) {
    return const PasswordAuthFailure(
      mode: PasswordAuthFailureMode.hostKeyDeclined,
      message:
          'Host key was not trusted. No password was sent and nothing was written. '
          'Use the manual install path, or try again after confirming the fingerprint.',
      offerRetry: false,
    );
  }

  if (!hostKeyVerified) {
    return const PasswordAuthFailure(
      mode: PasswordAuthFailureMode.connectionFailed,
      message:
          'Could not connect to the host. Check network, host address, and SSH port. '
          'This is not a password error.',
      offerRetry: false,
    );
  }

  if (!passwordMethodOffered) {
    return const PasswordAuthFailure(
      mode: PasswordAuthFailureMode.passwordDisabled,
      message:
          'Password authentication is not available on this server. '
          'The server did not offer password login. Use the manual install path instead.',
      offerRetry: false,
    );
  }

  return const PasswordAuthFailure(
    mode: PasswordAuthFailureMode.rejected,
    message:
        'Authentication failed. Check the username and password, then try again '
        'or use the manual install path.',
    offerRetry: true,
  );
}

/// Maps dartssh2 / socket errors onto [classifyPasswordAuthFailure] inputs.
///
/// Prefer [serverAuthMethods] from the server when present. Message heuristics
/// are used only when that set is empty, to distinguish disabled vs rejected.
///
/// When [hostKeyDeclined] is true (user cancelled TOFU), that wins over
/// connection-failure copy even if [hostKeyAccepted] is false.
PasswordAuthFailure classifySshBootstrapError(
  Object error, {
  required bool hostKeyAccepted,
  required Set<String> serverAuthMethods,
  bool hostKeyDeclined = false,
}) {
  if (hostKeyDeclined) {
    return classifyPasswordAuthFailure(
      error: error,
      hostKeyVerified: false,
      passwordMethodOffered: false,
      hostKeyDeclined: true,
    );
  }

  if (!hostKeyAccepted || _isConnectionFailure(error)) {
    return classifyPasswordAuthFailure(
      error: error,
      hostKeyVerified: false,
      passwordMethodOffered: false,
    );
  }

  final passwordOffered = _passwordMethodOffered(
    error: error,
    serverAuthMethods: serverAuthMethods,
  );

  return classifyPasswordAuthFailure(
    error: error,
    hostKeyVerified: true,
    passwordMethodOffered: passwordOffered,
  );
}

bool _isConnectionFailure(Object error) {
  if (error is TimeoutException ||
      error is SocketException ||
      error is SSHSocketError ||
      error is SSHHandshakeError ||
      error is SSHHostkeyError ||
      error is SSHDisconnectError) {
    return true;
  }
  if (error is SSHAuthAbortError) {
    final reason = error.reason;
    if (reason is SSHHostkeyError ||
        reason is SSHSocketError ||
        reason is SSHDisconnectError ||
        reason is SSHHandshakeError) {
      return true;
    }
    final hay = '${error.message} ${reason ?? ''}'.toLowerCase();
    if (hay.contains('host key') ||
        hay.contains('socket') ||
        hay.contains('network') ||
        hay.contains('timed out') ||
        hay.contains('timeout')) {
      return true;
    }
  }
  return false;
}

bool _passwordMethodOffered({
  required Object error,
  required Set<String> serverAuthMethods,
}) {
  if (serverAuthMethods.isNotEmpty) {
    return serverAuthMethods.contains('password');
  }
  return !_messageSuggestsPasswordDisabled(error);
}

bool _messageSuggestsPasswordDisabled(Object error) {
  final hay = error.toString().toLowerCase();
  if (hay.contains('passwordauthentication') &&
      (hay.contains('disabled') ||
          hay.contains('off') ||
          hay.contains('no'))) {
    return true;
  }
  if (hay.contains('password authentication disabled') ||
      hay.contains('password not offered') ||
      hay.contains('no password method') ||
      hay.contains('password login disabled') ||
      hay.contains('password authentication is not available')) {
    return true;
  }
  return false;
}
