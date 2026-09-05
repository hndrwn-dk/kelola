import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/presentation/screens/terminal_sheet.dart';
import 'package:kelola/providers.dart';

void main() {
  testWidgets('sheet copy is a command runner, not a live terminal',
      (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    const host = Host(
      id: 'h1',
      alias: 'east-worker-uat',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
      keyAlias: 'kelola',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(home: CommandSheet(host: host)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Terminal'), findsOneWidget);
    expect(find.textContaining('NO PTY'), findsOneWidget);
    expect(find.text(commandRunnerEmptyCopy), findsOneWidget);
    expect(find.text('connected…'), findsNothing);
    expect(find.text('SSH'), findsNothing);
    expect(find.textContaining('one command'), findsOneWidget);
    expect(find.text('Propose'), findsOneWidget);
  });
}
