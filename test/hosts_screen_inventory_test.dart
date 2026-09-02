import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  testWidgets('hosts home groups by status and shows a summary strip',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final now = DateTime.now().toUtc();

    final nas = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.updateAttention(
      id: nas.id,
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 91,
      attentionAt: now.subtract(const Duration(minutes: 4)),
    );
    await repo.saveFacts(
      nas.id,
      const HostFacts(
        osId: 'debian',
        osVersionId: '12',
        prettyName: 'Debian 12',
        init: InitSystem.systemd,
        systemdVersion: 252,
        pkg: PackageManager.apt,
        fw: FirewallBackend.nftables,
        hasJournald: true,
        journalReadable: true,
        arch: 'x86_64',
      ),
    );

    final dbHost = await repo.insert(
      alias: 'db-primary',
      address: '10.0.4.12',
      port: 22,
      username: 'hendra',
    );
    await repo.updateAttention(
      id: dbHost.id,
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 40,
      attentionAt: now.subtract(const Duration(minutes: 2)),
    );

    await repo.insert(
      alias: 'ub',
      address: '127.0.0.1',
      port: 22,
      username: 'hendra',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HostsScreen), findsOneWidget);
    expect(
      find.text('3 hosts · 1 needs attention · 1 healthy · 1 not checked'),
      findsOneWidget,
    );
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('NOT CHECKED'), findsOneWidget);
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.text('db-primary'), findsOneWidget);
    expect(find.text('ub'), findsOneWidget);
    expect(
      find.text('2 failed · disk 91% · checked 4m ago'),
      findsOneWidget,
    );
    expect(find.byType(OsIcon), findsWidgets);
    expect(find.byType(SectionSlab), findsNWidgets(3));
  });

  testWidgets('healthy group over 8 hosts collapses until the header is tapped',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final now = DateTime.now().toUtc();
    for (var i = 1; i <= 9; i++) {
      final host = await repo.insert(
        alias: 'ok-$i',
        address: '10.0.0.$i',
        port: 22,
        username: 'hendra',
      );
      await repo.updateAttention(
        id: host.id,
        attention: HostAttention.healthy,
        failedUnitCount: 0,
        diskRootPercent: 20,
        attentionAt: now.subtract(const Duration(minutes: 1)),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HEALTHY · 9'), findsOneWidget);
    expect(find.text('ok-1'), findsNothing);
    expect(find.text('ok-9'), findsNothing);

    await tester.tap(find.text('HEALTHY · 9'));
    await tester.pumpAndSettle();

    expect(find.text('ok-1'), findsOneWidget);
    expect(find.text('ok-9'), findsOneWidget);
  });
}
