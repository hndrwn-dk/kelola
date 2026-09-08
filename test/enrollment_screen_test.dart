import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/ssh/openssh_ecdsa.dart';
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
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}
