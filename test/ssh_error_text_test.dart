import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';

void main() {
  test('unwraps SSHAuthAbortError reason from dartssh2', () {
    final error = SSHAuthAbortError(
      'Connection closed before authentication',
      SSHDisconnectError(3, 'no matching cipher found'),
    );
    expect(describeSshError(error), contains('no matching cipher found'));
  });

  test('host-key rejection names the check, not the handshake', () {
    final text = describeSshError(SSHHostkeyError('mismatch'));
    expect(
      text,
      'The host key was rejected. Confirm the fingerprint before continuing.',
    );
    expectConnectionCopy(text);
  });

  test('explains login failure', () {
    expect(
      describeSshError(SSHAuthFailError('publickey')),
      contains('authorized_keys'),
    );
  });

  test('SocketException no-route does not imply SSH port changed', () {
    final error = SocketException(
      'No route to host',
      osError: const OSError('No route to host', 113),
      address: InternetAddress('192.168.18.114'),
      port: 51942, // Dart reports local ephemeral port — not SSH 22
    );
    final text = describeSshError(error);
    expect(text, 'No route to 192.168.18.114. Check Wi-Fi/VPN.');
    expect(text, isNot(contains('51942')));
    expectConnectionCopy(text);
  });

  test('SocketException connection refused omits ephemeral port', () {
    final error = SocketException(
      'Connection refused',
      osError: const OSError('Connection refused', 111),
      address: InternetAddress('10.0.0.5'),
      port: 48123,
    );
    final text = describeSshError(error);
    expect(text, 'Connection refused by 10.0.0.5. Check that the host is up.');
    expect(text, isNot(contains('48123')));
    expectConnectionCopy(text);
  });

  test('login timeout does not lecture about pinning or ports', () {
    final text = describeSshError(TimeoutException('ssh'));
    expect(
      text,
      'Timed out waiting for SSH login. Check Wi-Fi/VPN and that the host is up.',
    );
    expectConnectionCopy(text);
  });

  test('server close keeps the server message and drops handshake jargon', () {
    final text = describeSshError(
      SSHDisconnectError(3, 'no matching cipher found'),
    );
    expect(text, 'Server closed the connection: no matching cipher found');
    expectConnectionCopy(text);
  });

  test(
    'auth abort without a server message does not name ciphers or types',
    () {
      final text = describeSshError(
        SSHAuthAbortError('Connection closed before authentication'),
      );
      expect(text, 'Connection closed before login. Try again.');
      expectConnectionCopy(text);
    },
  );
}

void expectConnectionCopy(String text) {
  final lower = text.toLowerCase();
  expect(lower, isNot(contains('ephemeral')));
  expect(lower, isNot(contains('raw socket')));
  expect(lower, isNot(contains('socket port')));
  expect(lower, isNot(contains('handshake')));
  expect(lower, isNot(contains('saved ssh')));
  expect(lower, isNot(contains('runtimetype')));
  expect(lower, isNot(contains('kex')));
  expect(lower, isNot(contains('share no cipher')));
}
