import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/llm/explain_sections.dart';
import 'package:kelola/data/llm/assist_service.dart';

void main() {
  test('failed-unit prompt requires labeled Cause / Error / Next Step sections',
      () {
    final system = AssistService.failedUnitSystemPrompt.toLowerCase();
    expect(system, contains('cause:'));
    expect(system, contains('concrete error line:'));
    expect(system, contains('next step:'));
    expect(system, isNot(contains('paragraph')));
    expect(system, contains('do not invent'));
  });

  test('disk prompt requires labeled What / Evidence / Next Step sections', () {
    final system = AssistService.diskSystemPrompt.toLowerCase();
    expect(system, contains('what:'));
    expect(system, contains('evidence:'));
    expect(system, contains('next step:'));
    expect(system, isNot(contains('paragraph')));
  });

  test('parseExplainSections extracts three non-empty sections', () {
    const raw = '''
**Cause:**
The unit failed because nginx.conf is invalid.

**Concrete Error Line:**
`nginx: configuration file /etc/nginx/nginx.conf test failed`

**Next Step:**
Inspect `/etc/nginx/nginx.conf` and fix the syntax error.
''';
    final parsed = parseExplainSections(raw, kind: ExplainKind.failedUnit);
    expect(parsed.isStructured, isTrue);
    expect(parsed.sections.map((s) => s.title).toList(), [
      'Cause',
      'Concrete Error Line',
      'Next Step',
    ]);
    expect(parsed.sections[0].body, contains('nginx.conf is invalid'));
    expect(parsed.sections[1].body, contains('nginx: configuration file'));
    expect(parsed.sections[2].body, contains('Inspect'));
    expect(parsed.sections.every((s) => s.body.trim().isNotEmpty), isTrue);
  });

  test('parseExplainSections drops empty headings', () {
    const raw = '''
Cause:
Unit crashed on start.

Concrete Error Line:

Next Step:
Check journalctl -u nginx.
''';
    final parsed = parseExplainSections(raw, kind: ExplainKind.failedUnit);
    expect(parsed.isStructured, isTrue);
    expect(parsed.sections.map((s) => s.title).toList(), [
      'Cause',
      'Next Step',
    ]);
  });

  test('unstructured prose is not fabricated into empty headings', () {
    const raw =
        'The cause of the failure is that the nginx configuration file '
        'is invalid. Check the config next.';
    final parsed = parseExplainSections(raw, kind: ExplainKind.failedUnit);
    expect(parsed.isStructured, isFalse);
    expect(parsed.sections, isEmpty);
    expect(parsed.fallback, raw);
  });

  test('same-line bodies after labels are still structured', () {
    const raw = '''
**Cause:** The unit failed because nginx.conf is invalid.
**Concrete Error Line:** `nginx: configuration file test failed`
**Next Step:** Inspect `/etc/nginx/nginx.conf`.
''';
    final parsed = parseExplainSections(raw, kind: ExplainKind.failedUnit);
    expect(parsed.isStructured, isTrue);
    expect(parsed.sections, hasLength(3));
    expect(parsed.sections[0].body, contains('nginx.conf is invalid'));
  });
}
