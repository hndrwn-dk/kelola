import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
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

  Future<void> pump(
    WidgetTester tester,
    Future<CommandRunnerResult?> Function(SnippetProbe probe) onExecute,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(hosts),
        ],
        child: KelolaApp(
          home: SnippetsScreen(host: _host, onExecute: onExecute),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openReadSnippet(WidgetTester tester) async {
    await tester.tap(find.text('df -PT'));
    await tester.pumpAndSettle();
  }

  testWidgets('a connection drop never shows an exit number', (tester) async {
    await pump(tester, (_) async {
      return commandRunFromExec(
        stdout: '',
        stderr: 'Connection closed by remote host',
        exitCode: null,
      );
    });
    await openReadSnippet(tester);
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no exit status'), findsOneWidget);
    expect(find.textContaining('exit -1'), findsNothing);
    expect(find.textContaining(RegExp(r'exit -?\d+')), findsNothing);
  });

  testWidgets('Run clears the previous transcript before the next result', (
    tester,
  ) async {
    final second = Completer<CommandRunnerResult>();
    var calls = 0;
    await pump(tester, (_) {
      calls++;
      if (calls == 1) {
        return Future.value(
          commandRunFromExec(stdout: 'OLD-OUTPUT\n', stderr: '', exitCode: 0),
        );
      }
      return second.future;
    });
    await openReadSnippet(tester);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(find.textContaining('OLD-OUTPUT'), findsOneWidget);
    expect(find.textContaining('exit 0'), findsOneWidget);

    await tester.tap(find.text('Run'));
    var sawRunning = false;
    for (var i = 0; i < 8 && !sawRunning; i++) {
      await tester.pump();
      expect(find.textContaining('OLD-OUTPUT'), findsNothing);
      expect(find.textContaining('exit 0'), findsNothing);
      sawRunning = find.text('Running').evaluate().isNotEmpty;
    }
    expect(sawRunning, isTrue);

    second.complete(
      commandRunFromExec(stdout: 'NEW-OUTPUT\n', stderr: '', exitCode: 1),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('OLD-OUTPUT'), findsNothing);
    expect(find.textContaining('NEW-OUTPUT'), findsOneWidget);
    expect(find.textContaining('exit 1'), findsOneWidget);
    expect(find.text('Running'), findsNothing);
  });
}
