import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/journal/journal_bookmark.dart';
import 'package:kelola/domain/journal/journal_view.dart';

void main() {
  test('bookmark label is Kelola copy plus the typed query', () {
    expect(
      journalBookmarkLabel(
        scope: JournalScope.system,
        priority: 3,
        lastHour: true,
        query: 'nginx',
      ),
      'SYSTEM · ERR+ · 1H · nginx',
    );
    expect(
      journalBookmarkLabel(
        unit: 'ssh.service',
        scope: JournalScope.all,
        lastHour: false,
        query: '  ',
      ),
      'SSH.SERVICE · ALL',
    );
  });

  test('same filter on the same host is one bookmark', () {
    final a = JournalBookmark(
      id: '1',
      hostId: 'h1',
      label: 'SYSTEM · ERR+',
      query: 'Nginx',
      scope: JournalScope.system,
      priority: 3,
      lastHour: false,
      createdAt: DateTime.utc(2026, 9, 27),
    );
    final b = JournalBookmark(
      id: '2',
      hostId: 'h1',
      label: 'other',
      query: 'nginx',
      scope: JournalScope.system,
      priority: 3,
      lastHour: false,
      createdAt: DateTime.utc(2026, 9, 28),
    );
    expect(sameJournalBookmark(a, b), isTrue);
    expect(
      sameJournalBookmark(a, b.copyWith(lastHour: true)),
      isFalse,
    );
    expect(
      sameJournalBookmark(a, b.copyWith(hostId: 'h2')),
      isFalse,
    );
  });
}
