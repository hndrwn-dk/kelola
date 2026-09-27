import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/session_logs/session_log.dart';

SessionLog _log({
  required String id,
  required DateTime createdAt,
  bool bookmarked = false,
  String title = 'uptime',
  String body = 'exit 0',
}) {
  return SessionLog(
    id: id,
    hostId: 'h1',
    title: title,
    body: body,
    createdAt: createdAt,
    bookmarked: bookmarked,
  );
}

void main() {
  test('skips empty titles and clips oversized bodies', () {
    expect(shouldRecordSessionLog(''), isFalse);
    expect(shouldRecordSessionLog('   '), isFalse);
    expect(shouldRecordSessionLog('uptime'), isTrue);
    expect(clipSessionLogBody('ok'), 'ok');

    final huge = 'x' * (kSessionLogBodyCap + 8);
    final clipped = clipSessionLogBody(huge);
    expect(clipped.length, lessThan(huge.length));
    expect(clipped, endsWith('---TRUNCATED---'));
    expect(clipped.startsWith('x'), isTrue);
  });

  test('retention drops stale logs but keeps bookmarks', () {
    final now = DateTime.utc(2026, 9, 27);
    final kept = pruneSessionLogs(
      logs: [
        _log(id: 'old', createdAt: DateTime.utc(2026, 8, 1)),
        _log(id: 'pin', createdAt: DateTime.utc(2026, 8, 1), bookmarked: true),
        _log(id: 'fresh', createdAt: DateTime.utc(2026, 9, 20)),
      ],
      now: now,
      retentionDays: 14,
    );
    expect(kept.map((l) => l.id), ['pin', 'fresh']);
  });

  test('cap keeps newest non-bookmarked and never drops bookmarks', () {
    final now = DateTime.utc(2026, 9, 27);
    final logs = <SessionLog>[
      _log(id: 'pin', createdAt: DateTime.utc(2026, 9, 1), bookmarked: true),
      for (var i = 0; i < kSessionLogCap + 2; i++)
        _log(
          id: 'n$i',
          createdAt: DateTime.utc(2026, 9, 10).add(Duration(minutes: i)),
        ),
    ];
    final kept = pruneSessionLogs(
      logs: logs,
      now: now,
      retentionDays: 30,
    );
    expect(kept, hasLength(kSessionLogCap + 1));
    expect(kept.any((l) => l.id == 'pin'), isTrue);
    expect(kept.any((l) => l.id == 'n0'), isFalse);
    expect(kept.any((l) => l.id == 'n${kSessionLogCap + 1}'), isTrue);
  });

  test('unknown retention days fall back to 14', () {
    expect(SessionLogRetention.fromDays(14).days, 14);
    expect(SessionLogRetention.fromDays(3), SessionLogRetention.fourteen);
    expect(SessionLogRetention.fourteen.label, '14 days');
  });
}
