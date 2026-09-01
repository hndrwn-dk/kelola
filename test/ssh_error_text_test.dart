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
}
