import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:kelola/domain/exceptions.dart';

String describeSshError(Object error) {
  if (error is SudoRequiredException) {
    return error.message;
  }
  if (error is TimeoutException) {
    return 'Timed out waiting for SSH login. Check Wi-Fi/VPN and that the host is up.';
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
    return 'Server closed the connection: ${error.message}';
  }
  if (error is SSHHostkeyError) {
    return 'The host key was rejected. Confirm the fingerprint before continuing.';
  }
  if (error is SSHAuthAbortError) {
    final reason = error.reason;
    if (reason is SSHDisconnectError) {
      return 'Server closed the connection: ${reason.message}';
    }
    if (reason is SSHHostkeyError) {
      return 'The host key was rejected. Confirm the fingerprint before continuing.';
    }
    return 'Connection closed before login. Try again.';
  }
  return error.toString();
}

String _describeSocketException(SocketException error) {
  final addr = error.address?.address ?? error.address?.host;
  final where = (addr == null || addr.isEmpty) ? 'the host' : addr;
  final hay = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
  final code = error.osError?.errorCode;

  if (code == 113 || hay.contains('no route to host')) {
    return 'No route to $where. Check Wi-Fi/VPN.';
  }
  if (code == 111 || hay.contains('connection refused')) {
    return 'Connection refused by $where. Check that the host is up.';
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
