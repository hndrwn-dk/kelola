import 'dart:async';
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
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/enrollment/password_auth_failure.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

void main() {
  final blob = Uint8List.fromList(List.filled(64, 1));
  final line = OpensshEcdsaP256.authorizedKeysLine(blob);
  final fingerprint = OpensshEcdsaP256.fingerprintSha256(blob);

  Future<void> pumpEnrollment(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: const KelolaApp(
          home: EnrollmentScreen(hostId: 'host-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'ready enrollment shows key, fingerprint, install commands, and Test; no QR',
    (tester) async {
      await pumpEnrollment(tester);

      expect(find.byType(EnrollmentScreen), findsOneWidget);
      expect(find.byType(KelolaCommand), findsWidgets);
      expect(find.textContaining(line), findsWidgets);
      expect(find.textContaining(fingerprint), findsOneWidget);
      expect(find.textContaining('mkdir -p ~/.ssh'), findsOneWidget);
      expect(find.textContaining("echo '$line' >> ~/.ssh/authorized_keys"),
          findsOneWidget);
      expect(find.textContaining('chmod 600 ~/.ssh/authorized_keys'),
          findsOneWidget);
      expect(find.text('Test connection'), findsOneWidget);
      expect(find.text('Install with password'), findsOneWidget);
      expect(
        find.textContaining('messaging'),
        findsNothing,
      );
      expect(
        find.textContaining('existing access'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cancel clears password and shows discarded only after clear',
    (tester) async {
      final password = _TrackingPassword()..set('super-secret');

      await tester.pumpWidget(
        KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    showPasswordEntrySheet(
                      context,
                      password: password,
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(password.isSet, isFalse);
      expect(password.clearCount, greaterThanOrEqualTo(1));
      expect(find.text('password discarded'), findsOneWidget);
    },
  );

  testWidgets(
    'passwordDisabled failure shows message and no retry',
    (tester) async {
      const failure = PasswordAuthFailure(
        mode: PasswordAuthFailureMode.passwordDisabled,
        message:
            'Password authentication is not available on this server. '
            'The server did not offer password login. Use the manual install path instead.',
        offerRetry: false,
      );

      await tester.pumpWidget(
        KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    showPasswordAuthFailureSheet(
                      context,
                      failure: failure,
                      passwordDiscarded: true,
                    );
                  },
                  child: const Text('fail'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Password authentication is not available'),
          findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Use manual path'), findsOneWidget);
      expect(find.text('password discarded'), findsOneWidget);
    },
  );

  testWidgets(
    'classifySshBootstrapError passwordDisabled path shows no retry',
    (tester) async {
      final failure = classifySshBootstrapError(
        SSHAuthFailError('All authentication methods failed'),
        hostKeyAccepted: true,
        serverAuthMethods: const {'publickey'},
      );
      expect(failure.mode, PasswordAuthFailureMode.passwordDisabled);
      expect(failure.offerRetry, isFalse);

      await tester.pumpWidget(
        KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    showPasswordAuthFailureSheet(
                      context,
                      failure: failure,
                      passwordDiscarded: true,
                    );
                  },
                  child: const Text('fail'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('fail'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Password authentication is not available'),
          findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Use manual path'), findsOneWidget);
    },
  );

  testWidgets(
    'verify HostKeyMismatchException shows mismatch UI not removal hint',
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
      final pool = _VerifyMismatchPool(repository: repo);

      await tester.pumpWidget(
        KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () async {
                    final verified = await verifyAfterPasswordKeyInstall(
                      context: context,
                      pool: pool,
                      host: host,
                    );
                    if (verified == false && context.mounted) {
                      await showKeyInstallReportSheet(
                        context,
                        report: buildKeyInstallReport(
                          append: const KeyInstallAppendResult(
                            kind: KeyInstallAppendKind.appended,
                            homeMode: 'drwx------',
                            createdSsh: false,
                          ),
                          verifyOk: false,
                          fullLine: line,
                        ),
                      );
                    }
                  },
                  child: const Text('verify'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('verify'));
      await tester.pumpAndSettle();

      expect(find.byType(HostKeyMismatchScreen), findsOneWidget);
      expect(find.textContaining('Host key changed'), findsOneWidget);
      expect(find.textContaining('delete that line'), findsNothing);
      expect(find.textContaining('Key present but not verified'), findsNothing);
    },
  );

  testWidgets(
    'verify-fail report shows removal hint',
    (tester) async {
      final report = buildKeyInstallReport(
        append: const KeyInstallAppendResult(
          kind: KeyInstallAppendKind.appended,
          homeMode: 'drwx------',
          createdSsh: false,
        ),
        verifyOk: false,
        fullLine: line,
      );

      await tester.pumpWidget(
        KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () {
                    showKeyInstallReportSheet(
                      context,
                      report: report,
                    );
                  },
                  child: const Text('report'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('report'));
      await tester.pumpAndSettle();

      expect(find.textContaining(line), findsOneWidget);
      expect(find.textContaining('authorized_keys'), findsWidgets);
      expect(
        find.textContaining('delete that line'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'append exec exception shows append failure not password auth retry',
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
      final pool = _AppendThrowFlowPool(repository: repo);

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

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Install this key?'), findsOneWidget);
      await tester.tap(find.text('Install this key'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Key install failed'), findsOneWidget);
      expect(
        find.textContaining('file state on the server is unknown'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
      expect(
        find.textContaining('Check the username and password'),
        findsNothing,
      );

      final audits = await repo.listAudit();
      expect(audits, hasLength(1));
      expect(audits.single.command, contains('append_failed'));
    },
  );

  testWidgets(
    'declined TOFU shows host-key declined not connection failure',
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
      final pool = _TofuDeclineFlowPool(repository: repo);

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

      await tester.enterText(find.byType(TextField), 'secret');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Unknown host key'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not connect'), findsNothing);
      expect(find.textContaining('Check network'), findsNothing);
      expect(find.textContaining('Host key was not trusted'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Use manual path'), findsOneWidget);

      final audits = await repo.listAudit();
      expect(audits, hasLength(1));
      expect(audits.single.errorSummary, 'hostKeyDeclined');
    },
  );
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _TrackingPassword extends EphemeralPassword {
  int clearCount = 0;

  @override
  void clear() {
    clearCount++;
    super.clear();
  }
}

class _VerifyMismatchPool extends SshSessionPool {
  _VerifyMismatchPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List.fromList(List.filled(64, 1)),
        );

  @override
  Future<T> verifyFreshKeyAuth<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
  }) async {
    throw HostKeyMismatchException(
      hostId: host.id,
      pinnedFingerprint: 'pinned-fp',
      seenFingerprint: 'seen-fp',
      algorithm: 'ssh-ed25519',
    );
  }
}

/// Authenticated bootstrap that invokes [body]; append exec throws.
class _AppendThrowFlowPool extends SshSessionPool {
  _AppendThrowFlowPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List.fromList(List.filled(64, 1)),
        );

  @override
  Future<T> runPasswordBootstrap<T>({
    required Host host,
    required EphemeralPassword password,
    required UnknownHostKeyHandler onUnknownHostKey,
    required Future<T> Function(SSHClient client) body,
  }) async {
    lastHostKeyAccepted = true;
    lastServerAuthMethods = const {'password'};
    // Client unused: [appendAuthorizedKeysLine] is overridden.
    return body(_FakeSshClient());
  }

  @override
  Future<KeyInstallAppendResult> appendAuthorizedKeysLine({
    required SSHClient client,
    required String keyBody,
    required String fullLine,
  }) async {
    throw TimeoutException('remote append exec timed out');
  }
}

/// Prompts TOFU then aborts like a declined unknown host key.
class _TofuDeclineFlowPool extends SshSessionPool {
  _TofuDeclineFlowPool({required HostRepository repository})
      : super(
          repository: repository,
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List.fromList(List.filled(64, 1)),
        );

  @override
  Future<T> runPasswordBootstrap<T>({
    required Host host,
    required EphemeralPassword password,
    required UnknownHostKeyHandler onUnknownHostKey,
    required Future<T> Function(SSHClient client) body,
  }) async {
    final accepted = await onUnknownHostKey(
      host.id,
      'ssh-ed25519',
      'SHA256:declined-fp',
    );
    lastHostKeyAccepted = accepted;
    lastHostKeyDeclined = !accepted;
    if (!accepted) {
      throw SSHAuthAbortError('host key rejected');
    }
    return body(_FakeSshClient());
  }
}

class _FakeSshClient extends Fake implements SSHClient {}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('enrollment test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('enrollment test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('enrollment test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
