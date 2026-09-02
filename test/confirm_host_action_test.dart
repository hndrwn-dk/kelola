import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';

void main() {
  testWidgets('destructive host action uses DestructiveConfirmSheet',
      (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmHostAction(
                  context,
                  hostAlias: 'nas-01',
                  title: 'Reboot nas-01?',
                  body: 'The host will reboot. SSH will drop until it comes back.',
                  confirmLabel: 'Reboot',
                  risk: RiskLevel.destructive,
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
    expect(find.text('Reboot nas-01?'), findsOneWidget);
  });
}
