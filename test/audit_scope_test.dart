import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  test('audit title is All hosts when scope is unset', () {
    expect(auditScreenTitle(null), 'Audit · All hosts');
    expect(auditScreenTitle(''), 'Audit · All hosts');
  });

  test('audit title uses the host alias when scoped', () {
    expect(
      auditScreenTitle('east-worker-uat'),
      'Audit · east-worker-uat',
    );
  });

  Future<void> pumpAudit(
    WidgetTester tester,
    KelolaDatabase db, {
    String? hostId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: KelolaApp(home: AuditScreen(hostId: hostId)),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('cross-host audit titles All hosts and lists every host',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final east = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.8',
      port: 22,
      username: 'hendra',
    );
    final nas = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.recordAudit(
      hostId: east.id,
      hostAlias: east.alias,
      remoteUser: 'hendra',
      title: 'Restarted nginx.service',
      command: 'sudo -n systemctl restart nginx.service',
      risk: 'mutate',
      usedSudo: true,
      exitCode: 0,
    );
    await repo.recordAudit(
      hostId: nas.id,
      hostAlias: nas.alias,
      remoteUser: 'hendra',
      title: 'Rebooted host',
      command: 'sudo -n reboot',
      risk: 'destructive',
      usedSudo: true,
      exitCode: 0,
    );

    await pumpAudit(tester, db);

    expect(find.text('Audit · All hosts'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsOneWidget);
    expect(find.text('Rebooted host'), findsOneWidget);
    expect(find.byType(FilterPill), findsWidgets);
    expect(find.text('ALL HOSTS'), findsOneWidget);
    expect(find.text('EAST-WORKER-UAT'), findsOneWidget);
    expect(find.text('NAS-01'), findsOneWidget);
  });

  testWidgets('host filter changes audit scope without leaving the screen',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final east = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.8',
      port: 22,
      username: 'hendra',
    );
    final nas = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.recordAudit(
      hostId: east.id,
      hostAlias: east.alias,
      remoteUser: 'hendra',
      title: 'Restarted nginx.service',
      command: 'sudo -n systemctl restart nginx.service',
      risk: 'mutate',
      usedSudo: true,
      exitCode: 0,
    );
    await repo.recordAudit(
      hostId: nas.id,
      hostAlias: nas.alias,
      remoteUser: 'hendra',
      title: 'Rebooted host',
      command: 'sudo -n reboot',
      risk: 'destructive',
      usedSudo: true,
      exitCode: 0,
    );

    await pumpAudit(tester, db, hostId: east.id);

    expect(find.text('Audit · east-worker-uat'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsOneWidget);
    expect(find.text('Rebooted host'), findsNothing);

    await tester.tap(find.text('NAS-01'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Audit · nas-01'), findsOneWidget);
    expect(find.text('Rebooted host'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsNothing);

    await tester.tap(find.text('ALL HOSTS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Audit · All hosts'), findsOneWidget);
    expect(find.text('Restarted nginx.service'), findsOneWidget);
    expect(find.text('Rebooted host'), findsOneWidget);
  });
}
