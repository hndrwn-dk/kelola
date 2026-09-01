import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

Future<bool> confirmUnitAction(
  BuildContext context, {
  required String hostAlias,
  required String unit,
  required UnitVerb verb,
}) async {
  final destructive = isDestructiveUnitAction(verb, unit);
  final risk = destructive ? RiskLevel.destructive : RiskLevel.mutate;
  final typed = TextEditingController();
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<KelolaColors>()!;
        return AlertDialog(
          title: Text('${verb.name} $unit?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (destructive)
                Text(
                  'This can drop SSH or networking on $hostAlias and lock you out.',
                  style: TextStyle(color: colors.red),
                )
              else
                Text(
                  'This changes state on $hostAlias.',
                  style: TextStyle(color: colors.muted),
                ),
              if (destructive) ...[
                const SizedBox(height: 12),
                Text(
                  'Type $hostAlias to confirm.',
                  style: TextStyle(color: colors.dim, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: typed,
                  autofocus: true,
                  decoration: InputDecoration(hintText: hostAlias),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (destructive && typed.text.trim() != hostAlias) {
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: colors.risk(risk),
                foregroundColor: const Color(0xFF1A1206),
              ),
              child: Text(verb.name),
            ),
          ],
        );
      },
    );
    return ok == true;
  } finally {
    typed.dispose();
  }
}
