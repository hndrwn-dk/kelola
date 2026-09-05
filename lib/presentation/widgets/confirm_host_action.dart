import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/risk/risk_level.dart';

Future<bool> confirmHostAction(
  BuildContext context, {
  required String hostAlias,
  required String title,
  required String body,
  required String confirmLabel,
  RiskLevel risk = RiskLevel.mutate,
  String? warning,
}) async {
  if (risk == RiskLevel.destructive) {
    var confirmed = false;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return KelolaSheet(
          child: DestructiveConfirmSheet(
            title: title,
            consequence: body,
            warning: warning ??
                'You will lose access immediately. Recovery needs physical or console access to the machine.',
            confirmToken: hostAlias,
            onConfirmed: () => confirmed = true,
          ),
        );
      },
    );
    return confirmed;
  }

  return showMutateConfirm(
    context,
    title: title,
    body: body,
    confirmLabel: confirmLabel,
  );
}
