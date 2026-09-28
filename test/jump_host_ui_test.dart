import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edit host shows via chain and disables a cycle pick',
      (tester) async {
    final edge = await repo.insert(
      alias: 'edge',
      address: '1.2.3.4',
      port: 22,
      username: 'ops',
    );
    final web = await repo.insert(
      alias: 'web',
      address: '10.0.0.10',
      port: 22,
      username: 'ops',
      jumpHostId: edge.id,
    );

    await pumpHome(tester, EditHostScreen(hostId: web.id));
    expect(find.text('via edge'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpHome(tester, EditHostScreen(hostId: edge.id));
    final webPill = tester
        .widgetList<FilterPill>(find.byType(FilterPill))
        .where((p) => p.label.toUpperCase() == 'WEB')
        .single;
    expect(webPill.enabled, isFalse);
  });

  testWidgets('add host can set a jump before enrollment', (tester) async {
    final edge = await repo.insert(
      alias: 'edge',
      address: '1.2.3.4',
      port: 22,
      username: 'ops',
    );

    await pumpHome(tester, const AddHostScreen());
    expect(find.text('Jump host'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('add-host-alias')), 'web');
    await tester.enterText(find.byKey(const Key('add-host-address')), '10.0.0.8');
    await tester.enterText(find.byKey(const Key('add-host-user')), 'ops');
    await tester.tap(find.text('EDGE'));
    await tester.pump();
    await tester.tap(find.text('Next — add the key'));
    await tester.pumpAndSettle();

    final created = (await repo.list()).where((h) => h.alias == 'web').single;
    expect(created.jumpHostId, edge.id);
  });

  testWidgets('hosts list meta includes via', (tester) async {
    final edge = await repo.insert(
      alias: 'edge',
      address: '1.2.3.4',
      port: 22,
      username: 'ops',
    );
    await repo.insert(
      alias: 'web',
      address: '10.0.0.10',
      port: 22,
      username: 'ops',
      jumpHostId: edge.id,
    );

    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.textContaining('via edge'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('enrollment mentions the jump host', (tester) async {
    final edge = await repo.insert(
      alias: 'edge',
      address: '1.2.3.4',
      port: 22,
      username: 'ops',
    );
    final web = await repo.insert(
      alias: 'web',
      address: '10.0.0.10',
      port: 22,
      username: 'ops',
      jumpHostId: edge.id,
    );

    await pumpHome(
      tester,
      EnrollmentScreen(
        hostId: web.id,
        hostAlias: web.alias,
        jumpVia: 'via edge',
      ),
    );
    expect(find.textContaining('reached through'), findsOneWidget);
    expect(find.textContaining('edge'), findsWidgets);
  });

  test('architecture: chain helper, hop cap, no VpnService', () {
    final chain = File('lib/domain/hosts/jump_chain.dart').readAsStringSync();
    final pool = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    final add = File('lib/presentation/screens/add_host_screen.dart')
        .readAsStringSync();
    final readme = File('README.md').readAsStringSync();
    expect(chain, contains('kMaxJumpHops'));
    expect(pool, contains('kMaxJumpHops'));
    expect(pool, contains('forwardLocal'));
    expect(pool, isNot(contains('VpnService')));
    expect(add, contains('jumpHostId'));
    expect(readme, contains('ProxyJump'));
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}
