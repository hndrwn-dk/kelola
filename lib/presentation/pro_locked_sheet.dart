import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';

/// Shared locked-feature sheet. [unavailable] leaves the sheet open: no
/// snackbar, dialog, or payment URL.
Future<void> showProLockedSheet(
  BuildContext context, {
  required String title,
  required String body,
  required Future<ProPurchaseResult> Function() onPurchase,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: ProLockedCard(
          title: title,
          body: body,
          onUnlock: () async {
            final result = await onPurchase();
            if (result != ProPurchaseResult.purchased || !ctx.mounted) {
              return;
            }
            Navigator.of(ctx).pop();
          },
        ),
      );
    },
  );
}
