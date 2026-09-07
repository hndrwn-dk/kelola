import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/assist_service.dart';

void main() {
  test('failed-unit system prompt requires labeled sections not paragraphs', () {
    final system = AssistService.failedUnitSystemPrompt;
    expect(system, contains('Cause:'));
    expect(system, contains('Concrete Error Line:'));
    expect(system, contains('Next Step:'));
    expect(system.toLowerCase(), isNot(contains('paragraph')));
    expect(system.toLowerCase(), contains('do not invent'));
    expect(system.toLowerCase(), contains('do not repeat'));
    expect(system.toLowerCase(), contains('sentence openers'));
  });
}
