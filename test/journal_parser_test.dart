import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/journal/journal_parser.dart';

void main() {
  test('parses NDJSON journal lines and skips junk', () {
    final raw = File('test/fixtures/journal/sample.ndjson').readAsStringSync();
    final page = const JournalParser().parse(raw, '');
    expect(page.entries, hasLength(2));
    expect(page.entries.first.unit, 'nginx.service');
    expect(page.entries.first.isError, isTrue);
    expect(page.entries.last.message, 'Hi');
  });

  test('permission denied with empty body', () {
    final page = const JournalParser().parse(
      '',
      'Permission denied',
    );
    expect(page.permissionDenied, isTrue);
  });
}
