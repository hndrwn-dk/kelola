import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/widgets/host_card.dart';
import 'package:kelola/providers.dart';

Future<void> _flushDriftStreams(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('hosts empty state invites the next action', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.textContaining('Add your first host'), findsOneWidget);
    await _flushDriftStreams(tester);
  });

  testWidgets('can remove a host from the list', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await HostRepository(db).insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendr',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('nas-01'), findsOneWidget);
    expect(find.byType(HostCard), findsNothing);
    expect(find.byTooltip('Remove host'), findsNothing);
    // Host inventory row; Fleet/AI Assist/Widget live in HostsUtilityRail.
    expect(find.byType(ServiceRow), findsOneWidget);
    expect(find.byType(HostsUtilityRail), findsOneWidget);
    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('Assist'), findsNothing);
    expect(find.text('AI Assist'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.byKey(HostsColophon.hairlineKey), findsOneWidget);

    await tester.fling(find.text('nas-01'), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(find.text('nas-01'), findsNothing);
    expect(find.textContaining('Add your first host'), findsOneWidget);
    await _flushDriftStreams(tester);
  });
}
