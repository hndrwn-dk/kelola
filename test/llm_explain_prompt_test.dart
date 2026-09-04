import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/assist_service.dart';

void main() {
  test('failed-unit system prompt caps reply at 3 short paragraphs', () {
    final system = AssistService.failedUnitSystemPrompt;
    expect(system.toLowerCase(), contains('3'));
    expect(system.toLowerCase(), contains('paragraph'));
    expect(system.toLowerCase(), contains('cause'));
    expect(system.toLowerCase(), contains('quote'));
    expect(system.toLowerCase(), contains('next step'));
    expect(system.toLowerCase(), contains('do not invent'));
    expect(system.toLowerCase(), contains('do not repeat'));
  });
}
