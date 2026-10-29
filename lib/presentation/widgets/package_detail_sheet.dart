import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';

/// Returns true when the user chose to update this package.
Future<bool> showPackageDetailSheet(
  BuildContext context, {
  required PackageUpdate update,
  required bool readOnly,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.kc;
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
          child: RiskBand(
            risk: update.security ? RiskLevel.mutate : RiskLevel.read,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        update.name,
                        style: KelolaType.mono(color: c.text, size: 15),
                      ),
                    ),
                    if (update.security)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(
                          'SEC',
                          style: KelolaType.mono(
                            color: c.amber,
                            size: 10,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  update.versionMeta.isEmpty
                      ? 'Version details unavailable.'
                      : update.versionMeta,
                  style: KelolaType.mono(color: c.muted, size: 12),
                ),
                const SizedBox(height: 14),
                if (!readOnly)
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(backgroundColor: c.red),
                    child: const Text('Update this package'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}
