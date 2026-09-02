import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

Future<void> showHostListActions(
  BuildContext context, {
  required String alias,
  required VoidCallback onEdit,
  required VoidCallback onRemove,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServiceRow(
              risk: RiskLevel.mutate,
              name: 'Edit host',
              meta: alias,
              onTap: () {
                Navigator.of(ctx).pop();
                onEdit();
              },
            ),
            const SizedBox(height: 6),
            ServiceRow(
              risk: RiskLevel.destructive,
              name: 'Remove',
              meta: alias,
              onTap: () {
                Navigator.of(ctx).pop();
                onRemove();
              },
            ),
          ],
        ),
      );
    },
  );
}
