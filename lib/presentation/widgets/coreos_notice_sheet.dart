import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

/// M48 §4 copy. Pinned by `coreos_node_test`.
const kCoreOsNoticeCopy =
    'This is an OpenShift node. Red Hat records SSH logins on nodes as an '
    '"accessed" mark that support may ask about. Kelola only reads. For '
    'cluster health, add the bastion instead.';

/// M48.1: OKD nodes (scos / fcos) have no Red Hat support behind them.
const kOkdNodeNoticeCopy =
    'This is an OKD node. SSH logins on nodes leave an "accessed" mark that '
    'the cluster shows on the node. Kelola only reads. For cluster health, '
    'add the bastion instead.';

bool _isOkdNode(String osId) => osId == 'scos' || osId == 'fcos';

/// `OKD node` for scos / fcos; `OpenShift node` otherwise (rhcos).
String coreOsNoticeTitle(String osId) =>
    _isOkdNode(osId) ? 'OKD node' : 'OpenShift node';

/// OKD copy for scos / fcos; [kCoreOsNoticeCopy] otherwise (rhcos).
String coreOsNoticeCopy(String osId) =>
    _isOkdNode(osId) ? kOkdNodeNoticeCopy : kCoreOsNoticeCopy;

/// First-connect notice for an RHCOS / SCOS / FCOS host. True = Continue.
/// Dismissing the sheet counts as Cancel.
Future<bool> showCoreOsNoticeSheet(
  BuildContext context, {
  required String osId,
}) async {
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
    builder: (ctx) => CoreOsNoticeSheetBody(osId: osId),
  );
  return ok ?? false;
}

class CoreOsNoticeSheetBody extends StatelessWidget {
  const CoreOsNoticeSheetBody({super.key, this.osId = 'rhcos'});

  final String osId;

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
              coreOsNoticeTitle(osId),
              style: KelolaType.display(
                color: c.text,
                size: 16,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              coreOsNoticeCopy(osId),
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
