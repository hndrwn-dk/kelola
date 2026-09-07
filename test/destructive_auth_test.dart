import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/destructive_auth.dart';

void main() {
  test('destructive risk always calls confirmPresence', () async {
    final signer = _CountingSigner();
    await requireDestructivePresence(
      signer,
      risk: RiskLevel.destructive,
      reason: 'Reboot',
    );
    expect(signer.presenceCalls, 1);
    expect(signer.lastReason, 'Reboot');
  });

  test('mutate and read skip confirmPresence', () async {
    final signer = _CountingSigner();
    await requireDestructivePresence(signer, risk: RiskLevel.mutate);
    await requireDestructivePresence(signer, risk: RiskLevel.read);
    expect(signer.presenceCalls, 0);
  });
}

class _CountingSigner implements HardwareSigner {
  int presenceCalls = 0;
  String? lastReason;

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    presenceCalls++;
    lastReason = reason;
  }

  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw UnimplementedError();
  }

  @override
  Future<bool> keyExists(String alias) async => true;

  @override
  Future<void> deleteKey(String alias) async {}
}
