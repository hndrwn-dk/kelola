import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/command_history/command_history.dart';

void main() {
  test('skips empty and whitespace-only lines', () {
    expect(shouldRecordCommandHistory(''), isFalse);
    expect(shouldRecordCommandHistory('   '), isFalse);
    expect(shouldRecordCommandHistory('uptime'), isTrue);
    expect(normalizeCommandHistoryLine('  df -h  '), 'df -h');
  });

  test('filter is case-insensitive substring and preserves order', () {
    const cmds = ['systemctl status nginx', 'uptime', 'SYSTEMCTL restart ssh'];
    expect(filterCommandHistory(cmds, ''), cmds);
    expect(filterCommandHistory(cmds, '  systemctl  '), [
      'systemctl status nginx',
      'SYSTEMCTL restart ssh',
    ]);
    expect(filterCommandHistory(cmds, 'zzz'), isEmpty);
  });
}
