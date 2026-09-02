import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
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

  Future<void> pumpHosts(WidgetTester tester) async {
    await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
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
  }

  testWidgets('long-press offers Edit host next to Remove', (tester) async {
    await pumpHosts(tester);

    await tester.longPress(find.text('nas-01'));
    await tester.pumpAndSettle();

    expect(find.text('Edit host'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.text('Edit host'));
    await tester.pumpAndSettle();

    expect(find.byType(EditHostScreen), findsOneWidget);
  });

  testWidgets('swipe toward edit opens the host editor', (tester) async {
    await pumpHosts(tester);

    await tester.fling(find.byType(Dismissible), const Offset(500, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(EditHostScreen), findsOneWidget);
  });
}
