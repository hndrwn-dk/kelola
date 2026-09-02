import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  testWidgets('type-to-confirm is static body text, not a floating label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: DestructiveConfirmSheet(
            title: 'Reboot nas-01?',
            consequence: 'The host will restart.',
            warning: 'SSH will drop.',
            confirmToken: 'nas-01',
            onConfirmed: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Type'), findsOneWidget);
    expect(find.textContaining('to confirm'), findsOneWidget);

    final hostName = tester.widget<RichText>(
      find.byWidgetPredicate((w) {
        if (w is! RichText) return false;
        return w.text.toPlainText().contains('Type nas-01 to confirm');
      }),
    );
    // Text.rich wraps the user span, so walk descendants rather than
    // only the RichText root's direct children.
    final spans = <TextSpan>[];
    void collect(InlineSpan span) {
      if (span is TextSpan) {
        spans.add(span);
        span.children?.forEach(collect);
      }
    }
    collect(hostName.text);
    final token = spans.firstWhere((s) => s.text == 'nas-01');
    expect(token.style?.fontFamily, 'IBMPlexMono');
    expect(token.style?.color, KelolaColors.dark.amber);
    expect(token.style?.fontSize, 15);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.labelText, isNull);
    expect(field.decoration?.hintText, isNotNull);

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'nas-01');
    await tester.pump();
    final armed = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(armed.onPressed, isNotNull);
  });
}
