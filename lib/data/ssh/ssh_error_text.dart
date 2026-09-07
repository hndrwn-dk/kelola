import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/domain/exceptions.dart';

String describeSshError(Object error) {
  if (error is SudoRequiredException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'Timed out waiting for SSH login. Pin the host key promptly, and check that the phone can reach the host address.';
  }
  if (error is SocketException) {
    return _describeSocketException(error);
  }
  if (error is SftpStatusError) {
    final msg = error.message.trim();
    return msg.isEmpty ? error.toString() : msg;
  }
  if (error is SftpError) {
    return error.message;
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

String _describeSocketException(SocketException error) {
  final addr = error.address?.address ?? error.address?.host;
  final where = (addr == null || addr.isEmpty) ? 'the host' : addr;
  final hay = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  final code = error.osError?.errorCode;

  if (code == 113 || hay.contains('no route to host')) {
    return 'No route to $where. The phone cannot reach it yet — common right after reboot. Kelola still uses the saved SSH port; the raw socket port is a local ephemeral port, not SSH.';
  }
  if (code == 111 || hay.contains('connection refused')) {
    return 'Connection refused by $where. sshd may still be starting after reboot. Kelola uses the host\'s saved SSH port.';
  }
  if (code == 110 || hay.contains('timed out') || hay.contains('timeout')) {
    return 'Timed out reaching $where. Check Wi-Fi/VPN and that the host is up.';
  }
  if (hay.contains('network is unreachable') || code == 101) {
    return 'Network unreachable to $where. Check Wi-Fi/VPN.';
  }

  final detail = error.osError?.message.trim();
  if (detail != null && detail.isNotEmpty) {
    return 'Network error to $where — $detail';
  }
  final msg = error.message.trim();
  if (msg.isNotEmpty) {
    return 'Network error to $where — $msg';
  }
  return 'Network error to $where.';
}
