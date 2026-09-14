import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/snippets/snippet.dart';
import 'package:kelola/domain/units/shell_quote.dart';
import 'package:kelola/presentation/screens/snippets_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  const df = Snippet(id: 'df', name: 'df -PT', template: 'df -PT {{path}}');

  String executed(String path) {
    final rendered = renderSnippet(df.template, SnippetBindings(path: path));
    final probe = snippetToProbe(df, SnippetBindings(path: path));
    expect(
      rendered.commandLine,
      probe.commandLine,
      reason: 'preview and execution must be the same render',
    );
    return probe.commandLine;
  }

  test('/tmp/a b stays one argument', () {
    expect(executed('/tmp/a b'), "df -PT ${shellSingleQuote('/tmp/a b')}");
    expect(executed('/tmp/a b'), "df -PT '/tmp/a b'");
  });

  test(r'$HOME is literal and does not expand', () {
    expect(executed(r'$HOME'), "df -PT ${shellSingleQuote(r'$HOME')}");
    expect(executed(r'$HOME'), r"df -PT '$HOME'");
  });

  test('/ ; echo INJECTED does not split into a second command', () {
    const value = '/ ; echo INJECTED';
    expect(executed(value), "df -PT ${shellSingleQuote(value)}");
    expect(executed(value), "df -PT '/ ; echo INJECTED'");
  });

  test('backtick and dollar-paren substitution stay literal', () {
    expect(executed('`id`'), "df -PT ${shellSingleQuote('`id`')}");
    expect(executed(r'$(id)'), "df -PT ${shellSingleQuote(r'$(id)')}");
  });

  test("an embedded single quote stays one intact value", () {
    expect(executed("it's"), "df -PT ${shellSingleQuote("it's")}");
    expect(executed("it's"), "df -PT 'it'\\''s'");
  });

  test('a newline stays inside one argument', () {
    const value = '/tmp/a\nb';
    expect(executed(value), "df -PT ${shellSingleQuote(value)}");
    expect(executed(value), "df -PT '/tmp/a\nb'");
  });

  test('an empty value does not produce a command or a quoted empty argument', () {
    for (final path in [null, '', '   ']) {
      final rendered = renderSnippet(df.template, SnippetBindings(path: path));
      expect(rendered.canRun, isFalse, reason: 'path=$path');
      expect(rendered.commandLine, isNull, reason: 'path=$path');
      expect(rendered.emptyPlaceholders, {'path'}, reason: 'path=$path');
      expect(
        () => snippetToProbe(df, SnippetBindings(path: path)),
        throwsA(isA<SnippetUnboundException>()),
        reason: 'path=$path',
      );
    }
  });

  test('static pipe text is not quoted', () {
    const listen = Snippet(
      id: 'listen',
      name: 'listen-on-port',
      template: r'ss -lptn | grep -F :{{port}}',
    );
    final rendered = renderSnippet(
      listen.template,
      const SnippetBindings(port: '22'),
    );
    final probe = snippetToProbe(listen, const SnippetBindings(port: '22'));
    expect(rendered.commandLine, probe.commandLine);
    expect(probe.commandLine, "ss -lptn | grep -F :${shellSingleQuote('22')}");
  });

  test('every placeholder is quoted, not only the first', () {
    const snippet = Snippet(
      id: 'both',
      name: 'both',
      template: 'echo {{host}} {{path}}',
    );
    const bindings = SnippetBindings(
      host: r'$HOME',
      path: '/ ; echo INJECTED',
    );
    final rendered = renderSnippet(snippet.template, bindings);
    final probe = snippetToProbe(snippet, bindings);
    expect(rendered.commandLine, probe.commandLine);
    expect(
      probe.commandLine,
      "echo ${shellSingleQuote(r'$HOME')} ${shellSingleQuote('/ ; echo INJECTED')}",
    );
  });
  const host = Host(
    id: 'h1',
    alias: 'nas-01',
    address: '10.0.0.8',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
  );

  late KelolaDatabase db;
  late HostRepository hosts;

  setUp(() {
    db = KelolaDatabase.memory();
    hosts = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> openDf(WidgetTester tester, List<String> executed) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(hosts),
        ],
        child: KelolaApp(
          home: SnippetsScreen(
            host: host,
            onExecute: (SnippetProbe probe) async {
              executed.add(probe.commandLine);
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('df -PT'));
    await tester.pumpAndSettle();
  }

  testWidgets('preview text is the command handed to execution', (tester) async {
    final executed = <String>[];
    await openDf(tester, executed);

    await tester.enterText(find.byType(TextField), '/ ; echo INJECTED');
    await tester.pump();

    const expected = "df -PT '/ ; echo INJECTED'";
    final preview = tester.widget<SelectableText>(find.byType(SelectableText)).data;
    expect(preview, expected);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();

    expect(executed, [preview]);
  });

  testWidgets('an empty template value disables Run and does not execute', (tester) async {
    final executed = <String>[];
    await openDf(tester, executed);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(find.text('Required'), findsOneWidget);
    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle();
    expect(executed, isEmpty);
  });
}
