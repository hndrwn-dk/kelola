import 'dart:async';

import 'package:dartssh2/dartssh2.dart';

String describeSshError(Object error) {
  if (error is TimeoutException) {
    return 'Timed out waiting for SSH login. Pin the host key promptly, and check that the phone can reach the host address.';
  }
  if (error is SSHAuthFailError) {
    return 'Login failed. Check the username and that this phone\'s public key is in ~/.ssh/authorized_keys.';
  }
  if (error is SSHDisconnectError) {
    return 'Server closed the handshake: ${error.message}';
  }
  if (error is SSHHostkeyError) {
    return 'The host key was rejected.';
  }
  if (error is SSHAuthAbortError) {
    final reason = error.reason;
    if (reason is SSHDisconnectError) {
      return 'Server closed the handshake: ${reason.message}';
    }
    if (reason is SSHHostkeyError) {
      return 'The host key was rejected.';
    }
    if (reason != null) {
      return 'Connection closed before login (${reason.runtimeType}: $reason).';
    }
    return 'Connection closed before login. Usually the host-key prompt failed during handshake, or this phone and the server share no cipher/KEX.';
  }
  return error.toString();
}
