import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/command_history/command_complete.dart';

void main() {
  test('empty query yields no suggestions', () {
    expect(completeCommandLines(query: '', history: const ['uptime']), isEmpty);
    expect(
      completeCommandLines(query: '   ', history: const ['uptime']),
      isEmpty,
    );
  });

  test('history prefix beats corpus and later substring', () {
    expect(
      completeCommandLines(
        query: 'sys',
        history: const [
          'systemctl status nginx',
          'uptime',
          'journalctl -u ssh',
        ],
        corpus: const ['systemctl restart', 'ss -lptn'],
      ),
      ['systemctl status nginx', 'systemctl restart'],
    );
  });

  test('history substring is used when nothing prefixes', () {
    expect(
      completeCommandLines(
        query: 'nginx',
        history: const ['systemctl status nginx', 'uptime'],
        corpus: const ['systemctl restart'],
      ),
      ['systemctl status nginx'],
    );
  });

  test('caps at 8 and de-dupes exact lines', () {
    final history = [for (var i = 0; i < 12; i++) 'cmd-$i'];
    final listed = completeCommandLines(
      query: 'cmd',
      history: history,
      corpus: const ['cmd-0', 'cmd-extra'],
    );
    expect(listed, hasLength(kCommandCompleteCap));
    expect(listed.first, 'cmd-0');
    expect(listed.where((c) => c == 'cmd-0'), hasLength(1));
  });

  test('command_complete.dart does not import the LLM module', () {
    final text = File('lib/domain/command_history/command_complete.dart')
        .readAsStringSync();
    expect(text.contains('package:kelola/domain/llm'), isFalse);
    expect(text.contains('package:kelola/data/llm'), isFalse);
  });
}
