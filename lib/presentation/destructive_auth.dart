import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Destructive actions always get a fresh presence prompt (single timed key).
Future<void> requireDestructivePresence(
  HardwareSigner signer, {
  required RiskLevel risk,
  String reason = 'Confirm destructive action',
}) async {
  if (risk != RiskLevel.destructive) {
    return;
  }
  await signer.confirmPresence(reason: reason);
}
