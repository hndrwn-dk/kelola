import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
import 'package:kelola/domain/enrollment/ephemeral_password.dart';
import 'package:kelola/domain/enrollment/key_install_outcome.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/enrollment/password_auth_failure.dart';
import 'package:kelola/presentation/enrollment/password_key_install_flow.dart';
import 'package:kelola/presentation/screens/enrollment_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
      expect(find.byType(QrImageView), findsNothing);
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
