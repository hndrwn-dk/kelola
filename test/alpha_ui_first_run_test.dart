import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'dart:io';

import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/screens/tofu_screen.dart';
import 'package:kelola/providers.dart';

TextStyle _spanStyle(InlineSpan span, String needle) {
  if (span is TextSpan) {
    final own = span.text;
    if (own != null && own.contains(needle) && span.style != null) {
      return span.style!;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      try {
        return _spanStyle(child, needle);
      } on StateError {
        continue;
      }
    }
  }
  throw StateError('no span for $needle in ${span.toPlainText()}');
}

void main() {
  test('dashboard poll label is duration, not network RTT', () {
    expect(dashboardPollLabel(5566), 'poll 5.6s');
    expect(dashboardPollLabel(1316), 'poll 1.3s');
    expect(
      dashboardSessionFacts(
        disconnected: false,
        uptime: '7h',
        pollMs: 5566,
      ),
      ['up 7h', 'poll 5.6s'],
    );
  });

  test('host list error copy is not the exception text', () {
    expect(
      hostInventoryErrorCopy(StateError('db exploded')),
      'Could not load hosts.',
    );
    expect(
      hostInventoryErrorCopy(StateError('db exploded')),
      isNot(contains('exploded')),
    );
  });

  testWidgets('all-interfaces port stands out from loopback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const Scaffold(
          body: PublishedPortText(
            ports: [
              PublishedPort(
                bind: '127.0.0.1',
                hostPort: 55432,
                containerPort: 5432,
              ),
              PublishedPort(
                bind: '0.0.0.0',
                hostPort: 8443,
                containerPort: 80,
              ),
            ],
          ),
        ),
      ),
    );
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate((w) {
        return w is RichText && w.text.toPlainText().contains('127.0.0.1');
      }),
    );
    final loopback = _spanStyle(rich.text, '127.0.0.1');
    final open = _spanStyle(rich.text, '0.0.0.0');
    expect(loopback.color, isNot(open.color));
    expect(open.color, KelolaColors.dark.amber);
    expect(loopback.color, KelolaColors.dark.dim);
    expect(open.fontWeight, FontWeight.w600);
    expect(loopback.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('session facts use readable body type, not 8.5 mono tracking',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: DashboardSessionFacts(
            facts: dashboardSessionFacts(
              disconnected: false,
              uptime: '7h',
              pollMs: 1316,
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('up 7h'));
    expect(text.style!.fontSize, 12);
    expect(text.style!.fontSize, greaterThan(8.5));
  });

  testWidgets('tofu uses IBM Plex, not Inter', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(
          home: TofuScreen(
            hostId: 'h1',
            algorithm: 'ecdsa-sha2-nistp256',
            fingerprint: 'SHA256:abc',
          ),
        ),
      ),
    );
    await tester.pump();
    final body = tester.widget<Text>(find.textContaining('first time Kelola'));
    expect(body.style!.fontFamily, 'IBMPlexSans');
    final fingerprint = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(fingerprint.style!.fontFamily, 'IBMPlexMono');
    expect(body.style!.fontFamily, isNot('Inter'));
  });

  test('host note and virtual filesystems are not stock Material', () {
    final dash = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(dash, contains('KelolaSheet'));
    expect(dash, isNot(contains('AlertDialog')));
    final disk = File('lib/presentation/screens/disk_screen.dart').readAsStringSync();
    expect(disk, contains('ServiceRow'));
    expect(disk, isNot(contains('ListTile')));
  });

  test('first-run copy uses host, and opens Containers', () {
    expect(
      File('lib/presentation/screens/hosts_screen.dart').readAsStringSync(),
      contains('Add your first host'),
    );
    expect(
      File('lib/presentation/screens/hosts_screen.dart').readAsStringSync(),
      isNot(contains('Add your first server')),
    );
    expect(
      File('lib/presentation/screens/enrollment_screen.dart').readAsStringSync(),
      contains('every host'),
    );
    expect(
      File('lib/presentation/screens/enrollment_screen.dart').readAsStringSync(),
      isNot(contains('every server')),
    );
    expect(
      File('lib/presentation/screens/host_key_mismatch_screen.dart')
          .readAsStringSync(),
      contains('the host was rebuilt'),
    );
    expect(
      File('lib/presentation/screens/firewall_screen.dart').readAsStringSync(),
      contains('on the host, not this phone'),
    );
    expect(
      File('lib/presentation/screens/host_dashboard_screen.dart')
          .readAsStringSync(),
      contains("label: 'Containers'"),
    );
    expect(
      File('lib/presentation/screens/host_dashboard_screen.dart')
          .readAsStringSync(),
      isNot(contains("label: 'Workloads'")),
    );
  });

  test('primary actions are amber filled buttons', () {
    String around(String path, String label) {
      final src = File(path).readAsStringSync();
      final at = src.indexOf(label);
      expect(at, greaterThan(0), reason: '$path missing $label');
      return src.substring(at < 280 ? 0 : at - 280, at);
    }

    expect(
      around('lib/presentation/screens/file_editor_screen.dart', "'Save'"),
      contains('FilledButton'),
    );
    expect(
      around('lib/presentation/screens/edit_host_screen.dart', "'Save'"),
      contains('FilledButton'),
    );
    expect(
      around('lib/presentation/screens/tunnels_screen.dart', "'Add'"),
      contains('FilledButton'),
    );
    expect(
      around('lib/presentation/screens/add_host_screen.dart', 'Next — add the key'),
      contains('FilledButton'),
    );
    for (final path in [
      'lib/presentation/screens/file_editor_screen.dart',
      'lib/presentation/screens/edit_host_screen.dart',
      'lib/presentation/screens/tunnels_screen.dart',
      'lib/presentation/screens/add_host_screen.dart',
    ]) {
      final primary = around(path, path.contains('tunnels')
          ? "'Add'"
          : path.contains('add_host')
              ? 'Next — add the key'
              : "'Save'");
      expect(primary, isNot(contains('TextButton(')));
    }
  });

  testWidgets('add host shows field errors, not a snackbar', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const KelolaApp(home: AddHostScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '').at(0), 'nas');
    await tester.enterText(find.byType(TextField).at(1), '10.0.0.2');
    await tester.enterText(find.byType(TextField).at(3), 'root');
    await tester.tap(find.text('Next — add the key'));
    await tester.pump();
    expect(
      find.text('Kelola does not log in as root. Use a sudoer.'),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    final hint = tester.widget<Text>(
      find.text(
        'Paste Host blocks. IdentityFile is ignored — this phone keeps one hardware key.',
      ),
    );
    expect(hint.style!.fontFamily, 'IBMPlexSans');
  });

  testWidgets('host list failure uses KelolaError, not the exception', (tester) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostsProvider.overrideWith(
            (ref) => Stream<List<Host>>.error(StateError('db exploded')),
          ),
        ],
        child: const KelolaApp(home: HostsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(KelolaError), findsOneWidget);
    expect(find.text('Could not load hosts.'), findsOneWidget);
    expect(find.textContaining('exploded'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
