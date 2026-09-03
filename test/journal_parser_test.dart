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

  test('empty json has a hint', () {
    final page = const JournalParser().parse('not json\n', '');
    expect(page.entries, isEmpty);
    expect(page.emptyHint, isNotNull);
  });

  test('incremental buffer holds a split line until the next chunk', () {
    final buf = JournalNdjsonBuffer();
    expect(
      buf.add(
        '{"__CURSOR":"a","__REALTIME_TIMESTAMP":"1","PRIORITY":"6","MESSAGE":"Hel',
      ),
      isEmpty,
    );
    expect(buf.pendingBytes, greaterThan(0));
    final got = buf.add('lo"}\n');
    expect(got, hasLength(1));
    expect(got.single.message, 'Hello');
    expect(buf.pendingBytes, 0);
  });

  test('incremental buffer skips a malformed line and keeps the next', () {
    final buf = JournalNdjsonBuffer();
    final got = buf.add(
      '{not json}\n{"__CURSOR":"b","__REALTIME_TIMESTAMP":"2","PRIORITY":"3","MESSAGE":"ok"}\n',
    );
    expect(got, hasLength(1));
    expect(got.single.message, 'ok');
    expect(got.single.isError, isTrue);
  });

  test('incremental buffer does not retain completed lines', () {
    final buf = JournalNdjsonBuffer();
    buf.add(
      '{"__CURSOR":"a","__REALTIME_TIMESTAMP":"1","PRIORITY":"6","MESSAGE":"x"}\n{"partial',
    );
    expect(buf.pendingBytes, lessThan(20));
  });

  test('parses rsyslog ISO lines from logger -t', () {
    const line =
        '2026-09-03T06:55:32.661499+00:00 east-worker-uat kelolatest: cobain 1788418532';
    final entry = JournalParser.tryParseLine(line);
    expect(entry, isNotNull);
    expect(entry!.message, 'cobain 1788418532');
    expect(entry.syslogIdentifier, 'kelolatest');
    expect(entry.realtimeUsec, isNotEmpty);
  });

  test('incremental buffer yields a syslog logger line', () {
    final buf = JournalNdjsonBuffer();
    final got = buf.add(
      '2026-09-03T06:55:32.661499+00:00 east-worker-uat kelolatest: cobain 1788418532\n',
    );
    expect(got, hasLength(1));
    expect(got.single.message, contains('cobain'));
  });
}

