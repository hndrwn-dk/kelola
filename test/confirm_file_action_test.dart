import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/widgets/confirm_file_action.dart';

void main() {
  DestructiveConfirmSheet sheetOf(WidgetTester tester) {
    return tester.widget<DestructiveConfirmSheet>(
      find.byType(DestructiveConfirmSheet),
    );
  }

  Future<void> openDelete(WidgetTester tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmFileDelete(
                  context,
                  hostAlias: 'nas-01',
                  path: '/var/log/app.log',
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
  }

  testWidgets('delete token is the file name', (tester) async {
    await openDelete(tester);
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sheetOf(tester).confirmToken, 'app.log');
  });

  testWidgets('lockout edit uses DestructiveConfirmSheet with file name token',
      (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                confirmFileMutate(
                  context,
                  hostAlias: 'edge',
                  path: '/etc/ssh/sshd_config',
                  title: 'Save sshd_config?',
                  body: 'Uploads the edited file.',
                  confirmLabel: 'Save',
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
    expect(sheetOf(tester).confirmToken, 'sshd_config');
    expect(find.textContaining('unreachable'), findsWidgets);
  });
}
