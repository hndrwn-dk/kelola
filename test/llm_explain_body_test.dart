import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/domain/llm/explain_sections.dart';
import 'package:kelola/presentation/widgets/llm_explain_body.dart';
import 'package:kelola/presentation/widgets/llm_output_body.dart';

void main() {
  testWidgets('structured output shows three distinct app headings',
      (tester) async {
    const raw = '''
**Cause:**
The unit failed because nginx.conf is invalid.

**Concrete Error Line:**
`nginx: configuration file /etc/nginx/nginx.conf test failed`

**Next Step:**
Inspect `/etc/nginx/nginx.conf`.
''';
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LlmExplainBody(
              source: raw,
              kind: ExplainKind.failedUnit,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CAUSE'), findsOneWidget);
    expect(find.text('CONCRETE ERROR LINE'), findsOneWidget);
    expect(find.text('NEXT STEP'), findsOneWidget);
    expect(find.textContaining('nginx.conf is invalid'), findsWidgets);
    expect(find.textContaining('nginx: configuration file'), findsWidgets);
    // Inline code still present as monospace content, not raw backticks around it alone.
    expect(find.byType(LlmOutputBody), findsWidgets);
  });

  testWidgets('unstructured output has no empty section headings',
      (tester) async {
    const raw =
        'The cause of the failure is that the nginx configuration file '
        'is invalid. Check the config next.';
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: LlmExplainBody(
            source: raw,
            kind: ExplainKind.failedUnit,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CAUSE'), findsNothing);
    expect(find.text('NEXT STEP'), findsNothing);
    expect(find.textContaining('The cause of the failure'), findsWidgets);
  });
}
