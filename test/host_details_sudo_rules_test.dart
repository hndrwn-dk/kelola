import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/support/support_links.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';
import 'package:kelola/presentation/screens/web_lens_screen.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';

// Host details → Kelola sudo rules.

const _p = 'hendra ALL=(root) NOPASSWD: ';

const _host = Host(
  id: 'h1',
  alias: 'web01',
  address: '192.168.1.10',
  port: 22,
  username: 'hendra',
  keyAlias: 'kelola-user',
  lastSeenAt: null,
);

const _readOnlyHost = Host(
  id: 'h1',
  alias: 'web01',
  address: '192.168.1.10',
  port: 22,
  username: 'hendra',
  keyAlias: 'kelola-user',
  lastSeenAt: null,
  readOnly: true,
);

const _facts = HostFacts(
  osId: 'ubuntu',
  osVersionId: '24.04',
  init: InitSystem.systemd,
  systemdVersion: 255,
  pkg: PackageManager.apt,
  fw: FirewallBackend.ufw,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

const _readable = KelolaSudoFiles(
  files: [
    KelolaSudoFile(
      path: kelolaSudoersPath,
      state: KelolaSudoFileState.present,
      lines: [
        '$_p/usr/sbin/reboot ""',
        '$_p/usr/bin/systemctl reload nginx.service',
      ],
    ),
    KelolaSudoFile(
      path: kelolaWebSudoersPath,
      state: KelolaSudoFileState.present,
      lines: ['$_p/usr/sbin/nginx -t'],
    ),
  ],
  listed: [],
);

const _hidden = KelolaSudoFiles(
  files: [
    KelolaSudoFile(
      path: kelolaSudoersPath,
      state: KelolaSudoFileState.present,
    ),
  ],
  listed: [
    '/usr/sbin/reboot ""',
    '/usr/bin/systemctl reload nginx.service',
    '/opt/backup/run.sh',
  ],
);

void main() {
  late List<({String path, String? line})> removed;
  late int reads;
  late int checks;
  late int passwordReads;

  setUp(() {
    removed = [];
    reads = 0;
    checks = 0;
    passwordReads = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    Host host = _host,
    KelolaSudoFiles files = _readable,
    KelolaSudoFiles? afterRemove,
    KelolaSudoFiles withPassword = _readable,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      KelolaApp(
        home: HostDetailsScreen(
          host: host,
          facts: _facts,
          checkSudoRules: () async {
            checks++;
            return false;
          },
          readSudoFiles: () async {
            reads++;
            return removed.isEmpty ? files : (afterRemove ?? files);
          },
          readSudoFilesWithPassword: (_) async {
            passwordReads++;
            return withPassword;
          },
          removeSudoRule: (_, r) async => removed.add(r),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.widgetWithText(ServiceRow, name);

  testWidgets('lists each Kelola file with its lines in plain words and mono', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('KELOLA SUDO RULES'), findsOneWidget);
    // Grouped by file, in file order, each path in mono.
    final kelola = find.text(kelolaSudoersPath);
    final web = find.text(kelolaWebSudoersPath);
    expect(kelola, findsOneWidget);
    expect(web, findsOneWidget);
    expect(find.text(kelolaUnitSudoersPath), findsNothing);
    final mono = KelolaType.mono(color: Colors.white).fontFamily;
    expect(tester.widget<Text>(kelola).style?.fontFamily, mono);
    expect(
      tester.getTopLeft(kelola).dy,
      lessThan(tester.getTopLeft(row('Reload nginx.service')).dy),
    );
    expect(
      tester.getTopLeft(row('Reload nginx.service')).dy,
      lessThan(tester.getTopLeft(web).dy),
    );
    expect(
      tester.getTopLeft(web).dy,
      lessThan(tester.getTopLeft(row('Test the nginx config')).dy),
    );
    // Plain words, then the exact command in mono.
    for (final (words, cmd) in const [
      ('Reboot the host', '/usr/sbin/reboot ""'),
      ('Reload nginx.service', '/usr/bin/systemctl reload nginx.service'),
      ('Test the nginx config', '/usr/sbin/nginx -t'),
    ]) {
      expect(row(words), findsOneWidget);
      final c = find.descendant(of: row(words), matching: find.text(cmd));
      expect(c, findsOneWidget);
      expect(tester.widget<Text>(c).style?.fontFamily, mono);
      expect(tester.widget<ServiceRow>(row(words)).risk, RiskLevel.destructive);
    }
    expect(find.widgetWithText(ServiceRow, 'Remove file'), findsNWidgets(2));
    expect(reads, 1);
  });

  testWidgets('removing one line: the exact command is the token', (tester) async {
    await pump(
      tester,
      afterRemove: const KelolaSudoFiles(
        files: [
          KelolaSudoFile(
            path: kelolaSudoersPath,
            state: KelolaSudoFileState.present,
            lines: ['$_p/usr/sbin/reboot ""'],
          ),
        ],
        listed: [],
      ),
    );
    final checksBefore = checks;
    await tester.tap(row('Reload nginx.service'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<DestructiveConfirmSheet>(
      find.byType(DestructiveConfirmSheet),
    );
    expect(sheet.confirmToken, '/usr/bin/systemctl reload nginx.service');
    expect(sheet.consequence, contains(kelolaSudoersPath));
    // Wrong text: Confirm stays off.
    await tester.enterText(find.byType(TextField), 'nginx.service');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    expect(removed, isEmpty);
    await tester.enterText(
      find.byType(TextField),
      '/usr/bin/systemctl reload nginx.service',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(removed, [
      (path: kelolaSudoersPath, line: '$_p/usr/bin/systemctl reload nginx.service'),
    ]);
    // Read again, and the outdated-rules row checked again.
    expect(reads, 2);
    expect(checks, greaterThan(checksBefore));
    expect(row('Reload nginx.service'), findsNothing);
    expect(row('Reboot the host'), findsOneWidget);
  });

  testWidgets('removing a whole file: the file name is the token', (tester) async {
    await pump(tester);
    final remove = find.widgetWithText(ServiceRow, 'Remove file');
    await tester.tap(remove.last);
    await tester.pumpAndSettle();
    final sheet = tester.widget<DestructiveConfirmSheet>(
      find.byType(DestructiveConfirmSheet),
    );
    expect(sheet.confirmToken, 'kelola-web');
    await tester.enterText(find.byType(TextField), 'kelola-web');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(removed, [(path: kelolaWebSudoersPath, line: null)]);
  });

  testWidgets('read-only host: every action off, and says why', (tester) async {
    await pump(tester, host: _readOnlyHost);
    expect(find.text('Host is read-only.'), findsOneWidget);
    for (final r in tester.widgetList<ServiceRow>(find.byType(ServiceRow))) {
      expect(r.onTap, isNull, reason: r.name);
    }
    await tester.tap(row('Reload nginx.service'));
    await tester.pumpAndSettle();
    expect(find.byType(DestructiveConfirmSheet), findsNothing);
    expect(removed, isEmpty);
  });

  testWidgets('unreadable files: what sudo -n -l reports, and a password read', (
    tester,
  ) async {
    await pump(tester, files: _hidden);
    expect(find.text(kelolaSudoersPath), findsOneWidget);
    expect(
      find.textContaining('The file contents need the sudo password.'),
      findsOneWidget,
    );
    // Kelola's listed rules, read-only; others are not shown.
    expect(row('Reboot the host'), findsOneWidget);
    expect(row('Reload nginx.service'), findsOneWidget);
    expect(find.textContaining('/opt/backup/run.sh'), findsNothing);
    expect(tester.widget<ServiceRow>(row('Reboot the host')).onTap, isNull);
    expect(tester.widget<ServiceRow>(row('Reboot the host')).risk, RiskLevel.read);
    await tester.tap(find.widgetWithText(TextButton, 'Read with password'));
    await tester.pumpAndSettle();
    expect(passwordReads, 1);
    // Now the file lines can be removed.
    expect(tester.widget<ServiceRow>(row('Reload nginx.service')).onTap, isNotNull);
    expect(find.textContaining('need the sudo password'), findsNothing);
  });

  test('the grant copy points to Host details instead of a hand edit', () {
    expect(webOneTapCertsLaterNote, contains(kelolaSudoRulesPlace));
    expect(webOneTapCertsLaterNote, isNot(contains('by hand')));
    expect(
      webOutdatedGrantFix('hendra', const ['/usr/sbin/nginx -t']),
      contains(kelolaSudoRulesPlace),
    );
    expect(kelolaSudoRulesPlace, 'Host details → Kelola sudo rules');
    final faq = kSupportFaq.firstWhere(
      (f) => f.question == 'Why does an action say sudo needs a password?',
    );
    expect(faq.answer, contains('open $kelolaSudoRulesPlace'));
  });

  testWidgets('no Kelola file: says so', (tester) async {
    await pump(tester, files: const KelolaSudoFiles(files: [], listed: []));
    expect(find.text('No Kelola sudo files on this host.'), findsOneWidget);
  });

  testWidgets('without the read callback the section is not shown', (tester) async {
    await tester.pumpWidget(
      const KelolaApp(home: HostDetailsScreen(host: _host, facts: _facts)),
    );
    await tester.pumpAndSettle();
    expect(find.text('KELOLA SUDO RULES'), findsNothing);
  });
}
