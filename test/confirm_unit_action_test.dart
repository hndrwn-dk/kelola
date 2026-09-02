import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';

void main() {
  testWidgets('lockout stop uses DestructiveConfirmSheet with hostname token',
      (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmUnitAction(
                  context,
                  hostAlias: 'nas-01',
                  unit: 'sshd.service',
                  verb: UnitVerb.stop,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Stop sshd.service?'), findsOneWidget);
    expect(find.textContaining('nas-01'), findsWidgets);
    expect(
      find.textContaining('end your session'),
      findsOneWidget,
    );
  });

  testWidgets('lockout restart uses DestructiveConfirmSheet', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmUnitAction(
                  context,
                  hostAlias: 'nas-01',
                  unit: 'NetworkManager.service',
                  verb: UnitVerb.restart,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('non-lockout stop stays a mutate dialog', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmUnitAction(
                  context,
                  hostAlias: 'nas-01',
                  unit: 'nginx.service',
                  verb: UnitVerb.stop,
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(MutateConfirmDialog), findsOneWidget);
    expect(find.byType(DestructiveConfirmSheet), findsNothing);

    final title = tester.widget<Text>(find.text('Stop nginx.service?'));
    expect(title.style?.fontFamily, 'SpaceGrotesk');
    final body = tester.widget<Text>(find.textContaining('changes state'));
    expect(body.style?.fontFamily, 'IBMPlexSans');
    final confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'stop'));
    expect(confirm.style?.backgroundColor?.resolve({}), KelolaColors.dark.amber);
  });
}
