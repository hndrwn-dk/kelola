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
    expect(
      describeSshError(error),
      contains('no matching cipher found'),
    );
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
    expect(text.toLowerCase(), contains('no route'));
    expect(text, contains('192.168.18.114'));
    expect(text, isNot(contains('51942')));
    expect(text.toLowerCase(), anyOf(contains('reboot'), contains('reach')));
  });

  test('SocketException connection refused omits ephemeral port', () {
    final error = SocketException(
      'Connection refused',
      osError: const OSError('Connection refused', 111),
      address: InternetAddress('10.0.0.5'),
      port: 48123,
    );
    final text = describeSshError(error);
    expect(text.toLowerCase(), contains('refused'));
    expect(text, contains('10.0.0.5'));
    expect(text, isNot(contains('48123')));
  });
}
