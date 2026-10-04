import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/widgets/llm_api_key_field.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    required LlmApiKeyField field,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(body: SingleChildScrollView(child: field)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saved key never enters a controller or the widget tree',
      (tester) async {
    const fullKey = 'sk-abcdefghij3W5x';
    await pumpField(
      tester,
      field: LlmApiKeyField(
        storedHint: '••••••••3W5x',
        onReplace: (_) async {},
        onRemove: () async {},
      ),
    );
    expect(find.textContaining(fullKey), findsNothing);
    expect(find.text('••••••••3W5x'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Replace key'), findsOneWidget);
    expect(find.text('Remove key'), findsOneWidget);
  });

  testWidgets('short-key hint shows dots only', (tester) async {
    await pumpField(
      tester,
      field: LlmApiKeyField(
        storedHint: '••••••••',
        onReplace: (_) async {},
        onRemove: () async {},
      ),
    );
    expect(find.text('••••••••'), findsOneWidget);
  });

  testWidgets('replace Save disabled for empty or whitespace; Cancel keeps hint',
      (tester) async {
    String? replaced;
    await pumpField(
      tester,
      field: LlmApiKeyField(
        storedHint: '••••••••3W5x',
        onReplace: (value) async {
          replaced = value;
        },
        onRemove: () async {},
      ),
    );
    await tester.tap(find.text('Replace key'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(replaced, isNull);

    await tester.enterText(find.byType(TextField), '   \n');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(replaced, isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('••••••••3W5x'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(replaced, isNull);
  });

  testWidgets('replace Save stores trimmed key', (tester) async {
    String? replaced;
    await pumpField(
      tester,
      field: LlmApiKeyField(
        storedHint: '••••••••3W5x',
        onReplace: (value) async {
          replaced = value;
        },
        onRemove: () async {},
      ),
    );
    await tester.tap(find.text('Replace key'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  sk-newkeyvalue99  \n');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(replaced, 'sk-newkeyvalue99');
  });

  testWidgets('empty state uses obscureText and eye toggle; paused resets hide',
      (tester) async {
    await pumpField(
      tester,
      field: const LlmApiKeyField(
        storedHint: null,
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.autofillHints ?? const <String>[], isEmpty);

    await tester.tap(find.byTooltip('Show API key'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
  });

  testWidgets('new-key draft notifies trimmed text to parent', (tester) async {
    String? draft;
    await pumpField(
      tester,
      field: LlmApiKeyField(
        storedHint: null,
        onDraftChanged: (value) => draft = value,
      ),
    );
    await tester.enterText(find.byType(TextField), '  sk-fresh-key  \n');
    await tester.pumpAndSettle();
    expect(draft, 'sk-fresh-key');
  });
}
