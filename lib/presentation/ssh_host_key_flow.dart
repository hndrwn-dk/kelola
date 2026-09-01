import 'package:flutter/material.dart';
import 'package:kelola/presentation/screens/tofu_screen.dart';

Future<bool> promptUnknownHostKey(
  BuildContext context, {
  required String hostId,
  required String algorithm,
  required String fingerprint,
}) async {
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return false;
  }
  final accepted = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => TofuScreen(
        hostId: hostId,
        algorithm: algorithm,
        fingerprint: fingerprint,
      ),
    ),
  );
  return accepted == true;
}
