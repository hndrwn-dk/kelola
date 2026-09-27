import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/command_history/command_complete.dart';
import 'package:kelola/domain/command_history/command_history.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/session_logs/session_log.dart';
import 'package:kelola/presentation/screens/terminal_sheet.dart';
import 'package:kelola/providers.dart';

const _host = Host(
  id: 'h1',
  alias: 'east-worker-uat',
  address: '10.0.0.1',
  port: 22,
  username: 'hendr',
  keyAlias: 'kelola',
);

Widget _sheet(KelolaDatabase db, {Host host = _host}) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: KelolaApp(home: CommandSheet(host: host)),
  );
}

void main() {
  testWidgets('sheet copy is a command runner, not a live terminal', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_sheet(db));
    await tester.pumpAndSettle();

    expect(find.text('east-worker-uat'), findsOneWidget);
    expect(find.textContaining('Terminal'), findsOneWidget);
    expect(find.textContaining('NO PTY'), findsOneWidget);
    expect(find.text(commandRunnerEmptyCopy), findsOneWidget);
    expect(find.text('connected…'), findsNothing);
    expect(find.text('SSH'), findsNothing);
    expect(find.textContaining('one command'), findsOneWidget);
    expect(find.text('Propose'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Logs'), findsOneWidget);
  });

  testWidgets('Logs empty copy is per-host and stays in the sheet', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_sheet(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.text(sessionLogEmptyCopy), findsOneWidget);
    expect(find.text(commandRunnerEmptyCopy), findsNothing);
    expect(find.textContaining('search session logs'), findsOneWidget);
  });

  testWidgets('Logs lists this host and restores the saved body', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );
    await repo.recordSessionLog(
      host.id,
      title: 'uptime',
      body: '\$ uptime\nexit 0',
    );

    await tester.pumpWidget(_sheet(db, host: host));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();

    expect(find.text('uptime'), findsOneWidget);
    await tester.tap(find.text('uptime'));
    await tester.pumpAndSettle();
    expect(find.textContaining('exit 0'), findsOneWidget);
    expect(find.text(sessionLogEmptyCopy), findsNothing);
  });

  testWidgets('History empty copy is per-host and stays in the sheet', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_sheet(db));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text(commandHistoryEmptyCopy), findsOneWidget);
    expect(find.text(commandRunnerEmptyCopy), findsNothing);
    expect(find.textContaining('search commands'), findsOneWidget);
  });

  testWidgets('History lists this host and filling a line restores output', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );
    await repo.recordCommandHistory(host.id, 'df -h');
    await repo.recordCommandHistory(host.id, 'uptime');

    await tester.pumpWidget(_sheet(db, host: host));
    await tester.pumpAndSettle();

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('uptime'), findsOneWidget);
    expect(find.text('df -h'), findsOneWidget);
    expect(find.text(commandRunnerEmptyCopy), findsNothing);

    await tester.tap(find.text('uptime'));
    await tester.pumpAndSettle();

    expect(find.text(commandRunnerEmptyCopy), findsOneWidget);
    expect(find.text('df -h'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'uptime');
  });

  testWidgets('History filter is a local substring', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );
    await repo.recordCommandHistory(host.id, 'uptime');
    await repo.recordCommandHistory(host.id, 'systemctl status nginx');

    await tester.pumpWidget(_sheet(db, host: host));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'SYS');
    await tester.pump();

    expect(find.text('systemctl status nginx'), findsOneWidget);
    expect(find.text('uptime'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pump();
    expect(find.text(commandHistoryNoMatchCopy), findsOneWidget);
  });

  testWidgets('typing offers local corpus then fills the field', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(_sheet(db));
    await tester.pumpAndSettle();

    expect(find.text('journalctl -u'), findsNothing);

    await tester.enterText(find.byType(TextField), 'journal');
    await tester.pumpAndSettle();

    expect(find.text('journalctl -u'), findsOneWidget);
    await tester.tap(find.text('journalctl -u'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'journalctl -u');
  });

  testWidgets('history prefix ranks above the static corpus', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );
    await repo.recordCommandHistory(host.id, 'journalctl -u kelola-agent');

    await tester.pumpWidget(_sheet(db, host: host));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'journal');
    await tester.pumpAndSettle();

    expect(find.text('journalctl -u kelola-agent'), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.textContaining('journalctl'))
        .map((w) => w.data)
        .toList();
    expect(texts.first, 'journalctl -u kelola-agent');
    expect(kCommandCompleteCorpus, contains('journalctl -u'));
  });
}
