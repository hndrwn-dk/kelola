import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/presentation/screens/tofu_screen.dart';
import 'package:kelola/providers.dart';

/// Pinning a first-seen host key always needs a fresh biometric, even while
/// the signing key's timed window would let SSH auth skip the prompt.
void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<bool?> pumpTofu(WidgetTester tester, _PresenceSigner signer) async {
    bool? popped;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          hardwareSignerProvider.overrideWithValue(signer),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const TofuScreen(
                        hostId: 'h1',
                        algorithm: 'ecdsa-sha2-nistp256',
                        fingerprint: 'SHA256:abc',
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('Pin and continue'));
    await settle(tester);
    return popped;
  }

  testWidgets('pin asks for presence before storing the key', (tester) async {
    final signer = _PresenceSigner();
    final popped = await pumpTofu(tester, signer);
    expect(signer.reasons, ['Pin host key']);
    expect(popped, isTrue);
    final pinned = await tester.runAsync(() => repo.pinnedKey('h1'));
    expect(pinned?.fingerprint, 'SHA256:abc');
  });

  testWidgets('cancelled biometric does not pin', (tester) async {
    final signer = _PresenceSigner(fail: true);
    final popped = await pumpTofu(tester, signer);
    expect(signer.reasons, ['Pin host key']);
    expect(popped, isNull);
    expect(find.byType(TofuScreen), findsOneWidget);
    expect(find.textContaining('was not pinned'), findsOneWidget);
    final pinned = await tester.runAsync(() => repo.pinnedKey('h1'));
    expect(pinned, isNull);
  });

  testWidgets('a storage failure is not blamed on the fingerprint',
      (tester) async {
    repo = _FailingPinRepository(db);
    final signer = _PresenceSigner();
    final popped = await pumpTofu(tester, signer);
    expect(signer.reasons, ['Pin host key']);
    expect(popped, isNull);
    expect(find.textContaining('Could not save the host key'), findsOneWidget);
    expect(find.textContaining('Fingerprint not confirmed'), findsNothing);
  });
}

class _FailingPinRepository extends HostRepository {
  _FailingPinRepository(super.db);

  @override
  Future<void> pinKey({
    required String hostId,
    required String algorithm,
    required String fingerprint,
  }) async {
    throw StateError('disk full');
  }
}

class _PresenceSigner implements HardwareSigner {
  _PresenceSigner({this.fail = false});

  final bool fail;
  final reasons = <String>[];

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    reasons.add(reason);
    if (fail) {
      throw HardwareSignerException('auth_failed');
    }
  }

  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('tofu test must not generate keys');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('tofu test must not sign');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
