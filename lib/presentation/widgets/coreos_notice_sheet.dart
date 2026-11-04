import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

/// M48 §4 copy. Pinned by `coreos_node_test`.
const kCoreOsNoticeCopy =
    'This is an OpenShift node. Red Hat records SSH logins on nodes as an '
    '"accessed" mark that support may ask about. Kelola only reads. For '
    'cluster health, add the bastion instead.';

/// First-connect notice for an RHCOS / SCOS / FCOS host. True = Continue.
/// Dismissing the sheet counts as Cancel.
Future<bool> showCoreOsNoticeSheet(BuildContext context) async {
  final c = context.kc;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) => const CoreOsNoticeSheetBody(),
  );
  return ok ?? false;
}

class CoreOsNoticeSheetBody extends StatelessWidget {
  const CoreOsNoticeSheetBody({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KelolaSheetDragHandle(),
            const SizedBox(height: 6),
            Text(
              'OpenShift node',
              style: KelolaType.display(
                color: c.text,
                size: 16,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              kCoreOsNoticeCopy,
              style: KelolaType.body(color: c.text, size: 13),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: c.amber),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'Continue',
                      style: KelolaType.display(
                        color: c.ink,
                        size: 14,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
