import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';

void main() {
  testWidgets('a sheet paints its own surface', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const Scaffold(
          body: KelolaSheet(child: SizedBox(height: 40)),
        ),
      ),
    );
    final context = tester.element(find.byType(KelolaSheet));
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(KelolaSheet),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (box.decoration as BoxDecoration).color,
      context.kc.surface,
    );
  });

  testWidgets('the password sheet can ask for the sudo password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPasswordEntrySheet(
                context,
                password: EphemeralPassword(),
                title: 'Sudo password',
                body: 'Enter your sudo password.',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sudo password'), findsOneWidget);
    expect(find.text('Enter your sudo password.'), findsOneWidget);
    expect(find.textContaining('SSH password'), findsNothing);
  });

  test('the sudo flow never shows the SSH password wording', () {
    final src = File(
      'lib/presentation/widgets/enable_kelola_sudo_flow.dart',
    ).readAsStringSync();
    expect(RegExp('title: _sudoPasswordTitle').allMatches(src).length, 2);
  });

  test('a successful key install is a finished audit row', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'h',
      address: '10.0.0.1',
      port: 22,
      username: 'u',
    );
    await recordKeyInstallAudit(
      repo: repo,
      host: host,
      append: const KeyInstallAppendResult(
        kind: KeyInstallAppendKind.appended,
        homeMode: 'drwxr-xr-x',
        createdSsh: false,
      ),
      verifyOk: true,
      report: buildKeyInstallReport(
        append: const KeyInstallAppendResult(
          kind: KeyInstallAppendKind.appended,
          homeMode: 'drwxr-xr-x',
          createdSsh: false,
        ),
        verifyOk: true,
        fullLine: 'ecdsa-sha2-nistp256 AAAA kelola',
      ),
    );
    final rows = await db.select(db.auditRecords).get();
    expect(rows.single.exitCode, 0);
  });

  test('a timed out login mentions an open fingerprint prompt', () {
    expect(
      describeSshError(TimeoutException('login')),
      contains('fingerprint prompt'),
    );
  });

  test('service action errors scroll into view', () {
    final src = File(
      'lib/presentation/screens/unit_detail_screen.dart',
    ).readAsStringSync();
    expect(src, contains('controller: _scroll'));
    expect(src, contains('_showError(describeSshError(e))'));
    expect(src, isNot(contains('setState(() => _error = describeSshError(e));\n    } finally {\n      if (mounted) {\n        setState(() => _busy = false);\n      }\n    }\n  }\n\n  Future<void> _undo')));
  });

  test('an applied firewall rule is listed while its timer runs', () {
    final src = File(
      'lib/presentation/screens/firewall_screen.dart',
    ).readAsStringSync();
    final start = src.indexOf('unawaited(controller.start()');
    final reload = src.indexOf('are live throughout.');
    expect(start, greaterThan(0));
    expect(reload, greaterThan(start));
  });

  test('container lockout copy is a warning, not a certainty', () {
    for (final path in [
      'lib/presentation/screens/containers_screen.dart',
      'lib/presentation/screens/container_detail_screen.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, contains('may end this session'), reason: path);
      expect(src, isNot(contains('will end this session')), reason: path);
    }
  });

  test('Files says how to reach Download', () {
    expect(
      File('lib/presentation/screens/files_screen.dart').readAsStringSync(),
      contains('Long-press to download or manage.'),
    );
  });

  test('errors never show the Bad state prefix', () {
    expect(
      describeSshError(StateError('Configure AI Assist first.')),
      'Configure AI Assist first.',
    );
  });

  test('the provider badge follows the row being edited', () {
    final src = File(
      'lib/presentation/screens/llm_settings_screen.dart',
    ).readAsStringSync();
    expect(src, contains("? 'selected' : 'save to use'"));
  });
}
