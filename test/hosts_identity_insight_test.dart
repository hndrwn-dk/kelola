import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  Future<void> pumpHosts(
    WidgetTester tester,
    KelolaDatabase db,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hosts root shows Kelola mark and wordmark with search and add only',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );

    await pumpHosts(tester, db);

    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.byType(KelolaBrandMark), findsOneWidget);
    expect(find.text('Kelola'), findsOneWidget);
    expect(find.text('Hosts'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Add host'), findsOneWidget);
    expect(find.byTooltip('Audit'), findsNothing);
    expect(find.byIcon(Icons.receipt_long_rounded), findsNothing);
  });

  testWidgets('empty 7-day audit hides the insight row', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );

    await pumpHosts(tester, db);

    expect(find.byType(AuditInsightRow), findsNothing);
    expect(find.textContaining('7 days'), findsNothing);
    expect(find.text('AUDIT'), findsNothing);
    expect(find.text('INSIGHTS AUDIT'), findsNothing);
  });

  testWidgets('hosts footer shows version and keys line on one row',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );

    await pumpHosts(tester, db);

    final version = find.text('v0.1.0');
    final keys = find.text('Keys stay on this device');
    expect(version, findsOneWidget);
    expect(keys, findsOneWidget);
    expect(find.text('Kelola'), findsOneWidget);

    final row = find.ancestor(of: version, matching: find.byType(Row));
    expect(row, findsWidgets);
    expect(
      find.descendant(of: row.first, matching: keys),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(version).dy,
      closeTo(tester.getTopLeft(keys).dy, 6),
    );
    expect(tester.getTopLeft(version).dx, lessThan(tester.getTopLeft(keys).dx));
    final gap =
        tester.getTopLeft(keys).dx - tester.getBottomRight(version).dx;
    expect(gap, inInclusiveRange(4, 16));
    expect(
      find.descendant(
        of: row.first,
        matching: find.byType(Expanded),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('hosts-colophon-hairline')), findsOneWidget);
  });

  testWidgets('insight row uses alert band and opens cross-host audit',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.recordAudit(
      hostId: host.id,
      hostAlias: host.alias,
      remoteUser: 'hendra',
      title: 'Restarted nginx.service',
      command: 'sudo -n systemctl restart nginx.service',
      risk: 'mutate',
      usedSudo: true,
      exitCode: 0,
    );
    await repo.recordAudit(
      hostId: host.id,
      hostAlias: host.alias,
      remoteUser: 'hendra',
      title: 'Rebooted host',
      command: 'sudo -n reboot',
      risk: 'destructive',
      usedSudo: true,
      exitCode: 0,
    );
    await repo.recordAudit(
      hostId: host.id,
      hostAlias: host.alias,
      remoteUser: 'hendra',
      title: 'Polled CPU',
      command: 'LC_ALL=C',
      risk: 'read',
      usedSudo: false,
      exitCode: null,
      errorSummary: 'SocketException',
    );

    await pumpHosts(tester, db);

    expect(find.byType(AuditInsightRow), findsOneWidget);
    expect(find.text('INSIGHTS AUDIT'), findsOneWidget);
    expect(find.text('AUDIT'), findsNothing);
    expect(
      find.text('7 days · 2 changes · 1 destructive · 1 failed'),
      findsOneWidget,
    );
    final slab = tester.getRect(find.text('INSIGHTS AUDIT'));
    final counts = tester.getRect(
      find.text('7 days · 2 changes · 1 destructive · 1 failed'),
    );
    expect(slab.bottom, lessThanOrEqualTo(counts.top + 1));
    final row = tester.widget<AuditInsightRow>(find.byType(AuditInsightRow));
    expect(row.kind, AuditInsightKind.alert);

    await tester.tap(find.byType(AuditInsightRow));
    await tester.pumpAndSettle();

    expect(find.byType(AuditScreen), findsOneWidget);
    expect(find.text('Audit · All hosts'), findsOneWidget);
    expect(find.text('ALL HOSTS'), findsOneWidget);
  });

  testWidgets('host dashboard does not show the Kelola wordmark', (tester) async {
    await tester.pumpWidget(
      const KelolaApp(
        home: Scaffold(
          body: HostDashboardMenuButton(
            onNote: _noop,
            onEdit: _noop,
            onDetails: _noop,
            onAudit: _noop,
            onRemove: _noop,
          ),
        ),
      ),
    );

    expect(find.text('Kelola'), findsNothing);
    expect(find.byType(KelolaBrandMark), findsNothing);
  });
}

void _noop() {}
