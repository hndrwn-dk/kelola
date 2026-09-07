import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/journal/journal_view.dart';

void main() {
  test('kicker names unit, scope, severity, or syslog', () {
    expect(
      journalKicker(unit: 'nginx.service', priority: 3),
      'NGINX.SERVICE · ERR+',
    );
    expect(
      journalKicker(priority: 4, scope: JournalScope.system),
      'SYSTEM · WARN+',
    );
    expect(journalKicker(), 'ALL JOURNALS · ALL');
    expect(
      journalKicker(scope: JournalScope.user, priority: 3),
      'USER · ERR+',
    );
    expect(journalKicker(syslog: true, priority: 3), 'SYSLOG · ERR+');
  });

  test('clock is HH:mm:ss from the entry timestamp', () {
    final t = DateTime.utc(2026, 9, 2, 1, 12, 4);
    expect(journalClock(t.toLocal()), matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(journalClock(DateTime(2026, 9, 2, 9, 12, 4)), '09:12:04');
  });
}
