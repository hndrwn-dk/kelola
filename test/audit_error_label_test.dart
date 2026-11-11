import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';

class _Custom implements Exception {}

void main() {
  test('known errors get fixed labels that survive obfuscation', () {
    expect(auditErrorLabel(TimeoutException('x')), 'TimeoutException');
    expect(auditErrorLabel(const SocketException('x')), 'SocketException');
    expect(auditErrorLabel(StateError('x')), 'StateError');
  });

  test('unknown errors fall back to the runtime type', () {
    expect(auditErrorLabel(_Custom()), '_Custom');
  });

  test('session pool audit rows no longer store runtimeType names', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, isNot(contains('errorSummary: e.runtimeType')));
    expect(src, contains('errorSummary: auditErrorLabel(e)'));
  });
}
