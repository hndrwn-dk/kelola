import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';

void main() {
  testWidgets('kicker shows READ-ONLY only when the host is read-only',
      (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: Column(
            children: [
              KickerLine(
                machine: 'UBUNTU 26.04 · UP 3H',
                readOnly: true,
              ),
              KickerLine(
                machine: 'DEBIAN 12 · UP 47D',
                readOnly: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('READ-ONLY'), findsOneWidget);
    expect(find.textContaining('WRITABLE'), findsNothing);
    expect(find.textContaining('ALLOW WRITES'), findsNothing);
    expect(find.text('UBUNTU 26.04 · UP 3H'), findsOneWidget);
    expect(find.text('DEBIAN 12 · UP 47D'), findsOneWidget);
  });

  testWidgets('overflow menu keeps Note, Edit host, Host details, Audit log, Remove host',
      (tester) async {
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: HostDashboardMenuButton(
            onNote: () {},
            onEdit: () {},
            onDetails: () {},
            onAudit: () {},
            onRemove: () {},
            onDiagnostic: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();

    expect(find.text('Note'), findsOneWidget);
    expect(find.text('Edit host'), findsOneWidget);
    expect(find.text('Host details'), findsOneWidget);
    expect(find.text('Diagnostic pack'), findsOneWidget);
    expect(find.text('Audit log'), findsOneWidget);
    expect(find.text('Remove host'), findsOneWidget);
    expect(find.text('Read-only'), findsNothing);
    expect(find.text('Allow writes'), findsNothing);
  });

  test('dashboard source no longer treats read-only as a menu action', () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, contains('HostDashboardMenuButton'));
    expect(src, contains('KickerLine'));
    expect(src, isNot(contains("value: 'ro'")));
  });

  test('cpu poll uses backoff and surfaces disconnect instead of swallowing',
      () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, contains('PollBackoff'));
    expect(src, contains('DISCONNECTED'));
    expect(src, contains("label: 'Network'"));
    expect(src, isNot(contains('} catch (_) {}')));
  });

  test('dashboard footer is a status line, not a HostFacts chip dump', () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, contains('DashboardStatusLine'));
    expect(src, isNot(contains('facts.init.name')));
    expect(src, isNot(contains('facts.pkg.name')));
    expect(src, isNot(contains('facts.fw.name')));
    expect(src, isNot(contains('facts.runtimes')));
  });
}
