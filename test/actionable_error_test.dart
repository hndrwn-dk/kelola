import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/sudo_hint.dart';

void main() {
  testWidgets('sudo ActionableError explains the failure and shows copyable sudoers',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: ActionableError.sudo(user: 'hendra'),
        ),
      ),
    );

    expect(find.text(sudoRequiredTitle), findsOneWidget);
    expect(find.textContaining('password'), findsWidgets);
    expect(find.textContaining('mutate'), findsWidgets);
    expect(find.textContaining('polkit'), findsOneWidget);
    expect(find.text(kelolaSudoersLine(user: 'hendra')), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, kelolaSudoersLine(user: 'hendra'));
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('KelolaError swaps sudo strings for ActionableError', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: KelolaError(
            message: SudoRequiredException().toString(),
            sudoUser: 'hendra',
          ),
        ),
      ),
    );

    expect(find.byType(ActionableError), findsOneWidget);
    expect(find.text(kelolaSudoersLine(user: 'hendra')), findsOneWidget);
    expect(find.text(SudoRequiredException().toString()), findsNothing);
  });

  testWidgets('KelolaError keeps ordinary errors as body copy', (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: KelolaError(message: 'Timed out waiting for SSH login.'),
        ),
      ),
    );

    expect(find.byType(ActionableError), findsNothing);
    expect(find.text('Timed out waiting for SSH login.'), findsOneWidget);
  });
}
