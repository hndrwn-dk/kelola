import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  Future<HostRepository> seed(
    KelolaDatabase db, {
    required List<({
      String title,
      String command,
      String risk,
      int? exit,
      String? error,
    })> rows,
  }) async {
    final repo = HostRepository(db);
    for (final row in rows) {
      await repo.recordAudit(
        hostId: 'h1',
        hostAlias: 'nas-01',
        remoteUser: 'hendra',
        title: row.title,
        command: row.command,
        risk: row.risk,
        usedSudo: row.risk != 'read',
        exitCode: row.exit,
        errorSummary: row.error,
        durationMs: 340,
      );
    }
    return repo;
  }

  Future<void> pumpAudit(WidgetTester tester, KelolaDatabase db) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(home: AuditScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('default view shows mutate titles, not LC_ALL=C reads',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await seed(db, rows: [
      (
        title: 'Polled dashboard',
        command: 'LC_ALL=C\ncat /proc/uptime',
        risk: 'read',
        exit: 0,
        error: null,
      ),
      (
        title: 'Restarted nginx.service',
        command: 'sudo -n systemctl restart nginx.service',
        risk: 'mutate',
        exit: 0,
        error: null,
      ),
    ]);

    await pumpAudit(tester, db);

    expect(find.text('Restarted nginx.service'), findsOneWidget);
    expect(find.text('Polled dashboard'), findsNothing);
    expect(find.text('LC_ALL=C'), findsNothing);
    expect(find.textContaining('Last 7 days'), findsOneWidget);
    expect(find.textContaining('1 changes'), findsOneWidget);
    expect(find.byType(FilterPill), findsOneWidget);
    expect(find.text('SHOW ALL ACTIVITY'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('Show all activity reveals read probes; export stays full',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await seed(db, rows: [
      (
        title: 'Polled dashboard',
        command: 'LC_ALL=C\ncat /proc/uptime',
        risk: 'read',
        exit: 0,
        error: null,
      ),
      (
        title: 'Restarted nginx.service',
        command: 'sudo -n systemctl restart nginx.service',
        risk: 'mutate',
        exit: 0,
        error: null,
      ),
    ]);

    await pumpAudit(tester, db);
    expect(find.byTooltip('Copy JSON'), findsOneWidget);

    await tester.tap(find.text('SHOW ALL ACTIVITY'));
    await tester.pump();

    expect(find.text('Polled dashboard'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsOneWidget);
  });

  testWidgets('failed records stand out in the default view', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await seed(db, rows: [
      (
        title: 'Polled dashboard',
        command: 'LC_ALL=C',
        risk: 'read',
        exit: 1,
        error: null,
      ),
      (
        title: 'Restarted nginx.service',
        command: 'sudo -n systemctl restart nginx.service',
        risk: 'mutate',
        exit: null,
        error: 'ReadOnlyViolation',
      ),
    ]);

    await pumpAudit(tester, db);

    expect(find.text('Polled dashboard'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsOneWidget);
    expect(find.textContaining('failed'), findsWidgets);
  });

  testWidgets('empty default view when only successful reads exist',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await seed(db, rows: [
      (
        title: 'Polled dashboard',
        command: 'LC_ALL=C',
        risk: 'read',
        exit: 0,
        error: null,
      ),
    ]);

    await pumpAudit(tester, db);

    expect(find.text('Restarted nginx.service'), findsNothing);
    expect(find.text('No changes'), findsOneWidget);
    expect(find.text('SHOW ALL ACTIVITY'), findsOneWidget);
  });

  testWidgets('tapping a row shows the raw command', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await seed(db, rows: [
      (
        title: 'Restarted nginx.service',
        command: 'sudo -n systemctl restart nginx.service',
        risk: 'mutate',
        exit: 0,
        error: null,
      ),
    ]);

    await pumpAudit(tester, db);
    await tester.tap(find.text('Restarted nginx.service'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('sudo -n systemctl restart nginx.service'), findsOneWidget);
  });
}
