import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/snippets/starters.dart';
import 'package:kelola/presentation/screens/snippets_screen.dart';
import 'package:kelola/providers.dart';

const _host = Host(
  id: 'h1',
  alias: 'nas-01',
  address: '10.0.0.8',
  port: 22,
  username: 'ops',
  keyAlias: 'kelola',
);

void main() {
  late KelolaDatabase db;
  late HostRepository hosts;

  setUp(() {
    db = KelolaDatabase.memory();
    hosts = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(hosts),
        ],
        child: KelolaApp(
          home: SnippetsScreen(host: _host, onExecute: (_) async => null),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edit changes the template and the run preview follows', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('df -PT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit snippet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'df edited');
    await tester.enterText(find.byType(TextField).at(1), 'echo edited');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('df edited'), findsOneWidget);
    expect(find.text('df -PT'), findsNothing);

    await tester.tap(find.text('df edited'));
    await tester.pumpAndSettle();
    expect(find.text('echo edited'), findsWidgets);
    expect(find.textContaining('df -PT {{path}}'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore starter snippets'));
    await tester.pumpAndSettle();

    expect(find.text('df edited'), findsOneWidget);
    expect(find.text('df -PT'), findsNothing);
    await tester.tap(find.text('df edited'));
    await tester.pumpAndSettle();
    expect(find.text('echo edited'), findsWidgets);
  });

  testWidgets('delete removes the entry and it stays gone after reopen', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(find.text('listen-on-port'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('listen-on-port'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pump(tester);

    expect(find.text('listen-on-port'), findsNothing);
    final stored = await hosts.listSnippets();
    expect(stored.map((s) => s.id), isNot(contains('starter-listen')));
  });

  testWidgets('Restore puts starters back and says so when nothing is missing', (
    tester,
  ) async {
    await hosts.listSnippets();
    await hosts.deleteSnippet('starter-listen');
    await pump(tester);
    expect(find.text('listen-on-port'), findsNothing);

    await tester.tap(find.text('Restore starter snippets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restored'), findsOneWidget);
    expect(find.text('listen-on-port'), findsOneWidget);

    await tester.tap(find.text('Restore starter snippets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already in the library'), findsOneWidget);
  });

  test('deleted starters stay gone after a fresh list, including a cleared library', () async {
    await hosts.listSnippets();
    await hosts.deleteSnippet('starter-df');
    expect(
      (await hosts.listSnippets()).map((s) => s.id),
      isNot(contains('starter-df')),
    );

    for (final snippet in await hosts.listSnippets()) {
      await hosts.deleteSnippet(snippet.id);
    }
    expect(await hosts.listSnippets(), isEmpty);
  });

  test(
    'restore puts back missing starters and does not overwrite an edit',
    () async {
      await hosts.listSnippets();
      await hosts.deleteSnippet('starter-status');
      await hosts.deleteSnippet('starter-listen');
      final edited = shippedSnippets.firstWhere((s) => s.id == 'starter-df');
      await hosts.upsertSnippet(
        Snippet(
          id: edited.id,
          name: 'df edited',
          template: 'echo edited',
          starter: false,
        ),
      );

      final added = await hosts.restoreStarterSnippets();
      expect(added, 2);

      final rows = await hosts.listSnippets();
      final ids = rows.map((s) => s.id).toList();
      expect(ids.where((id) => id == 'starter-status').length, 1);
      expect(ids.where((id) => id == 'starter-listen').length, 1);
      expect(ids.where((id) => id == 'starter-df').length, 1);

      final df = rows.firstWhere((s) => s.id == 'starter-df');
      expect(df.name, 'df edited');
      expect(df.template, 'echo edited');
      expect(df.starter, isFalse);

      expect(await hosts.restoreStarterSnippets(), 0);
      expect((await hosts.listSnippets()).length, rows.length);
    },
  );
}
