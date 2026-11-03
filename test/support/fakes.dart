import 'dart:async';
import 'dart:typed_data';

import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/providers.dart';

/// Shared test doubles. New tests import these instead of copying them.

/// Every Pro feature locked or unlocked at once.
class FixedEntitlement implements Entitlement {
  FixedEntitlement({required this.unlocked});

  final bool unlocked;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void dispose() => _changes.close();

  @override
  void initialize() {}

  @override
  bool isUnlocked(ProFeature feature) => unlocked;

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  String get sourceLabel => 'std';

  @override
  String? get priceLabel => null;
}

/// Enrollment that already has a key, so screens skip key generation.
class ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

/// Signer that fails the test if anything tries to open a real SSH session.
class NoSshSigner implements HardwareSigner {
  NoSshSigner([this.why = 'this test must not open SSH']);

  final String why;

  @override
  Future<HardwareKey> generateKey(String alias) async => throw StateError(why);

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async =>
      throw StateError(why);

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async =>
      throw StateError(why);

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
