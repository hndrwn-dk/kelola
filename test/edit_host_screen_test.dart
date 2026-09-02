import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  Future<String> seed() async {
    final host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    await repo.pinKey(
      hostId: host.id,
      algorithm: 'ssh-ed25519',
      fingerprint: 'SHA256:pinned',
    );
    return host.id;
  }

  Future<void> pumpEditor(WidgetTester tester, String hostId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: KelolaApp(home: EditHostScreen(hostId: hostId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('alias save does not show DestructiveConfirmSheet', (tester) async {
    final id = await seed();
    await pumpEditor(tester, id);

    await tester.enterText(find.byKey(const Key('edit-host-alias')), 'files');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsNothing);
    expect((await repo.get(id))!.alias, 'files');
  });

  testWidgets('address change warns, then resets the pin', (tester) async {
    final id = await seed();
    await pumpEditor(tester, id);

    await tester.enterText(find.byKey(const Key('edit-host-address')), '10.0.0.9');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.textContaining('pinned'), findsWidgets);
    expect(await repo.pinnedKey(id), isNotNull);

    await tester.enterText(find.byType(TextField).last, 'nas-01');
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(await repo.pinnedKey(id), isNull);
    expect((await repo.get(id))!.address, '10.0.0.9');
  });

  testWidgets('username change warns about authorized_keys and keeps the pin',
      (tester) async {
    final id = await seed();
    await pumpEditor(tester, id);

    await tester.enterText(find.byKey(const Key('edit-host-username')), 'ops');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.textContaining('authorized_keys'), findsWidgets);
    expect(await repo.pinnedKey(id), isNotNull);

    await tester.enterText(find.byType(TextField).last, 'nas-01');
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(await repo.pinnedKey(id), isNotNull);
    expect((await repo.get(id))!.username, 'ops');
  });
}
