import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session pool writes probe title and full command, not first shell token',
      () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('AuditDraft.fromProbe'));
    expect(src, contains('draft.title'));
    expect(src, contains('draft.command'));
    expect(src, isNot(contains("split('\\n').first")));
    expect(src, contains("errorSummary: 'ReadOnlyViolation'"));
  });

  test('host key policy records a human title', () {
    final src = File('lib/data/ssh/host_key_policy.dart').readAsStringSync();
    expect(src, contains("title: 'Host key mismatch'"));
  });
}
