import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/journal/journal_view.dart';

void main() {
  test('kicker names the unit and the active severity filter', () {
    expect(
      journalKicker(unit: 'nginx.service', priority: 3),
      'NGINX.SERVICE · ERR+',
    );
    expect(journalKicker(priority: 4), 'SYSTEM · WARN+');
    expect(journalKicker(), 'SYSTEM · ALL');
  });

  test('clock is HH:mm:ss from the entry timestamp', () {
    final t = DateTime.utc(2026, 9, 2, 1, 12, 4);
    expect(journalClock(t.toLocal()), matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    expect(journalClock(DateTime(2026, 9, 2, 9, 12, 4)), '09:12:04');
  });
}
