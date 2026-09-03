import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/hosts/dashboard_status.dart';
import 'package:kelola/domain/sudo_hint.dart';

void main() {
  final now = DateTime.utc(2026, 9, 2, 8);
  final checked = now.subtract(const Duration(minutes: 4));

  test('default status is only Checked relative time', () {
    expect(
      dashboardStatusLine(checkedAt: checked, now: now),
      'Checked 4m ago',
    );
  });

  test('read-only host appends read-only', () {
    expect(
      dashboardStatusLine(checkedAt: checked, now: now, readOnly: true),
      'Checked 4m ago · read-only',
    );
  });

  test('sudo-needed appends the mutate-will-fail sentence', () {
    expect(
      dashboardStatusLine(
        checkedAt: checked,
        now: now,
        sudoNeedsPassword: true,
      ),
      'Checked 4m ago · $sudoMutateWillFail',
    );
  });

  test('read-only and sudo coexist on one line', () {
    expect(
      dashboardStatusLine(
        checkedAt: checked,
        now: now,
        readOnly: true,
        sudoNeedsPassword: true,
      ),
      'Checked 4m ago · read-only · $sudoMutateWillFail',
    );
  });

  testWidgets('default footer shows Checked and not HostFacts chips',
      (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: DashboardStatusLine(checkedAt: checked, now: now),
        ),
      ),
    );

    expect(find.text('Checked 4m ago'), findsOneWidget);
    expect(find.textContaining('systemd'), findsNothing);
    expect(find.textContaining('apt'), findsNothing);
    expect(find.textContaining('ufw'), findsNothing);
    expect(find.textContaining('docker'), findsNothing);
    expect(find.textContaining('x86_64'), findsNothing);
    expect(find.textContaining('read-only'), findsNothing);
    expect(find.textContaining('sudo needs a password'), findsNothing);
  });

  testWidgets('read-only footer includes read-only', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: DashboardStatusLine(
            checkedAt: checked,
            now: now,
            readOnly: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('Checked 4m ago'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
  });

  testWidgets('sudo footer opens copyable sudoers on tap', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: DashboardStatusLine(
            checkedAt: checked,
            now: now,
            sudoNeedsPassword: true,
            sudoUser: 'hendra',
          ),
        ),
      ),
    );

    expect(find.textContaining(sudoMutateWillFail), findsOneWidget);
    await tester.tap(find.textContaining('sudo needs a password'));
    await tester.pumpAndSettle();

    expect(find.byType(ActionableError), findsOneWidget);
    expect(
      find.text(kelolaSudoHint(user: 'hendra').snippet),
      findsOneWidget,
    );
    expect(find.textContaining('visudo -f /etc/sudoers.d/kelola'), findsWidgets);
  });

  testWidgets('combined footer is one wrapping row', (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: DashboardStatusLine(
            checkedAt: checked,
            now: now,
            readOnly: true,
            sudoNeedsPassword: true,
            sudoUser: 'hendra',
          ),
        ),
      ),
    );

    expect(find.byType(DashboardStatusLine), findsOneWidget);
    expect(find.textContaining('Checked 4m ago'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.textContaining(sudoMutateWillFail), findsOneWidget);
  });
}
