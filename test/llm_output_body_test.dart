import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/presentation/widgets/llm_output_body.dart';
import 'dart:io';

void main() {
  test('stripLlmMarkdown removes bold and code markers', () {
    const raw = '**Cause:**\n'
        'failed\n'
        '**Line:**\n'
        '`nginx.conf test failed`\n'
        '```\nsudo systemctl status nginx\n```';
    final plain = stripLlmMarkdown(raw);
    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('`')));
    expect(plain, contains('Cause:'));
    expect(plain, contains('nginx.conf test failed'));
    expect(plain, contains('sudo systemctl status nginx'));
  });

  testWidgets('renders bold/code without literal asterisks or backticks',
      (tester) async {
    const raw = '**Cause:** the unit failed.\n\n'
        'Error: `nginx: test failed`\n\n'
        '```\njournalctl -u nginx\n```\n';
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LlmOutputBody(source: raw),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cause:'), findsWidgets);
    expect(find.textContaining('nginx: test failed'), findsWidgets);
    expect(find.textContaining('journalctl -u nginx'), findsWidgets);

    final allText = find.byType(RichText);
    for (final e in allText.evaluate()) {
      final rich = e.widget as RichText;
      final plain = rich.text.toPlainText();
      expect(plain, isNot(contains('**')));
      expect(plain.contains('`nginx'), isFalse);
    }
  });

  testWidgets('malformed markdown does not throw; shows stripped text',
      (tester) async {
    // Unbalanced fences / bold — must not crash.
    const raw = '**open bold `code without close\n```partial';
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(body: LlmOutputBody(source: raw)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LlmOutputBody), findsOneWidget);
  });

  testWidgets('long single-token line does not overflow painter', (tester) async {
    final long = 'x' * 400;
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: LlmOutputBody(source: '`$long`'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('only one LlmOutputBody class; Explain and Assist result use it', () {
    final lib = Directory('lib');
    final hits = <String>[];
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) {
        continue;
      }
      final src = f.readAsStringSync();
      if (src.contains('class LlmOutputBody')) {
        hits.add(f.path.replaceAll('\\', '/'));
      }
    }
    expect(hits, hasLength(1));
    expect(hits.single, contains('llm_output_body.dart'));

    final incident =
        File('lib/presentation/widgets/incident_sheet.dart').readAsStringSync();
    final assist =
        File('lib/presentation/assist_flow.dart').readAsStringSync();
    expect(incident, contains('LlmExplainBody'));
    expect(assist, contains('LlmOutputBody'));
    // No parallel plain Text body for explain/result.
    expect(incident, isNot(contains('child: Text(\n                        explainResult!')));
  });
}
