import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/providers.dart';

const _testPassword = 'canary-pw-7xK9!not-in-audit';

void main() {
  group('non-persistence canaries', () {
    test('host_repository.dart does not reference EphemeralPassword', () {
      final src =
          File('lib/data/db/host_repository.dart').readAsStringSync();
      expect(src, isNot(contains('EphemeralPassword')));
    });

    test('hosts table has no password column', () {
      final src = File('lib/data/db/tables.dart').readAsStringSync();
      expect(src, isNot(matches(r'\bTextColumn get password\b')));
      expect(src, isNot(matches(r'\bIntColumn get password\b')));
    });
  });

  group('recordKeyInstallAudit', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late Host host;
    late String fullLine;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      host = await repo.insert(
        alias: 'pi',
        address: '127.0.0.1',
        port: 22,
        username: 'pi',
      );
      final blob = Uint8List.fromList(List.filled(64, 1));
      fullLine = OpensshEcdsaP256.authorizedKeysLine(blob);
    });

    tearDown(() => db.close());

    for (final scenario in _auditScenarios) {
      test('${scenario.name} audit omits password material', () async {
        final report = buildKeyInstallReport(
          append: scenario.append,
          verifyOk: scenario.verifyOk,
          fullLine: fullLine,
        );

        await recordKeyInstallAudit(
          repo: repo,
          host: host,
          append: scenario.append,
          verifyOk: scenario.verifyOk,
          report: report,
        );

        assertAuditsExcludePassword(await repo.listAudit(), _testPassword);
        expect(await repo.listAudit(), hasLength(1));
      });
    }
  });

  testWidgets(
    'runPasswordKeyInstallFlow auth failure audit omits password material',
    (tester) async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final host = await repo.insert(
        alias: 'pi',
        address: '127.0.0.1',
        port: 22,
        username: 'pi',
      );
      final pool = _AuthFailFlowPool(
        repository: repo,
        error: SSHAuthFailError('Authentication failed: $_testPassword'),
      );

      await _pumpPasswordInstallFlow(
        tester,
        db: db,
        repo: repo,
        host: host,
        pool: pool,
      );

      await tester.enterText(find.byType(TextField), _testPassword);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Use manual path'), findsOneWidget);
      await tester.tap(find.text('Use manual path'));
      await tester.pumpAndSettle();

      final audits = await repo.listAudit();
      expect(audits, hasLength(1));
      assertAuditsExcludePassword(audits, _testPassword);
    },
  );
}

void assertAuditsExcludePassword(List<AuditEvent> audits, String password) {
  for (final audit in audits) {
    expect(audit.title, isNot(contains(password)), reason: 'title');
    expect(audit.command, isNot(contains(password)), reason: 'command');
    expect(audit.hostAlias, isNot(contains(password)), reason: 'hostAlias');
    expect(audit.remoteUser, isNot(contains(password)), reason: 'remoteUser');
    final summary = audit.errorSummary;
    if (summary != null) {
      expect(summary, isNot(contains(password)), reason: 'errorSummary');
    }
  }
}

Future<void> _pumpPasswordInstallFlow(
  WidgetTester tester, {
  required KelolaDatabase db,
  required HostRepository repo,
  required Host host,
  required SshSessionPool pool,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        hostRepositoryProvider.overrideWithValue(repo),
        sessionPoolProvider.overrideWithValue(pool),
        enrollmentProvider.overrideWith(_ReadyEnrollment.new),
      ],
      child: KelolaApp(
        home: Consumer(
          builder: (context, ref, _) {
            return Scaffold(
              body: TextButton(
                onPressed: () => runPasswordKeyInstallFlow(
                  context: context,
                  ref: ref,
                  hostId: host.id,
                ),
                child: const Text('start'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('start'));
  await tester.pumpAndSettle();
}

class _AuditScenario {
  const _AuditScenario({
    required this.name,
    required this.append,
    required this.verifyOk,
  });

  final String name;
  final KeyInstallAppendResult append;
  final bool verifyOk;
}

const _auditScenarios = [
  _AuditScenario(
    name: 'appended + verified',
    append: KeyInstallAppendResult(
      kind: KeyInstallAppendKind.appended,
      homeMode: 'drwx------',
      createdSsh: false,
    ),
    verifyOk: true,
  ),
  _AuditScenario(
    name: 'already present + verified',
    append: const KeyInstallAppendResult(
      kind: KeyInstallAppendKind.alreadyPresent,
      homeMode: 'drwx------',
      createdSsh: false,
    ),
    verifyOk: true,
  ),
  _AuditScenario(
    name: 'append failed',
    append: const KeyInstallAppendResult(
      kind: KeyInstallAppendKind.failed,
      homeMode: 'unknown',
      createdSsh: false,
    ),
    verifyOk: false,
  ),
  _AuditScenario(
    name: 'appended + verify failed',
    append: const KeyInstallAppendResult(
      kind: KeyInstallAppendKind.appended,
      homeMode: 'drwx------',
      createdSsh: false,
    ),
    verifyOk: false,
  ),
  _AuditScenario(
    name: 'already present + verify failed',
    append: const KeyInstallAppendResult(
      kind: KeyInstallAppendKind.alreadyPresent,
      homeMode: 'drwx------',
      createdSsh: false,
    ),
    verifyOk: false,
  ),
];

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _AuthFailFlowPool extends SshSessionPool {
  _AuthFailFlowPool({
    required HostRepository repository,
    required this.error,
  }) : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List.fromList(List.filled(64, 1)),
        );

  final Object error;

  @override
  Future<T> runPasswordBootstrap<T>({
    required Host host,
    required EphemeralPassword password,
    required UnknownHostKeyHandler onUnknownHostKey,
    required Future<T> Function(SSHClient client) body,
  }) async {
    lastHostKeyAccepted = true;
    lastServerAuthMethods = const {'password'};
    throw error;
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('audit test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('audit test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('audit test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
