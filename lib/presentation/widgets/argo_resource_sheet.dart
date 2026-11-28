import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';

/// M49: read-only detail of one resource an Argo CD Application manages,
/// for kinds Kelola has no screen for. Server text is mono. No actions.
Future<void> showArgoResourceSheet(
  BuildContext context,
  ArgoResource resource,
) {
  final c = context.kc;
  return showModalBottomSheet<void>(
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
    builder: (ctx) => ArgoResourceSheetBody(resource: resource),
  );
}

class ArgoResourceSheetBody extends StatelessWidget {
  const ArgoResourceSheetBody({super.key, required this.resource});

  final ArgoResource resource;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final r = resource;
    final maxBody = kelolaSheetMaxBodyHeight(context);
    final msg = r.healthMessage;
    return KelolaSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KelolaSheetDragHandle(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: KelolaType.mono(color: c.text, size: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          r.kind,
                          style: KelolaType.mono(color: c.muted, size: 11),
                        ),
                      ],
                    ),
                  ),
                ),
                KelolaChromeIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (maxBody * 0.7).clamp(120.0, maxBody),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: RiskBand.forHealth(
                  status: argoResourceStatus(r),
                  child: FactGroup(
                    heading: null,
                    framed: false,
                    entries: [
                      FactEntry(label: 'Kind', value: r.kind),
                      if (r.group.isNotEmpty)
                        FactEntry(label: 'Group', value: r.group),
                      if (r.namespace.isNotEmpty)
                        FactEntry(label: 'Namespace', value: r.namespace),
                      FactEntry(label: 'Sync status', value: argoSyncLabel(r.sync)),
                      FactEntry(
                        label: 'Health',
                        value: argoHealthLabel(r.health),
                      ),
                      if (msg != null && msg.isNotEmpty)
                        FactEntry(label: 'Message', value: msg),
                      if (r.requiresPruning)
                        const FactEntry(label: 'Pruning', value: 'required'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resource status for its band or row: red only for degraded or missing,
/// amber for out of sync, green only when synced and healthy, else neutral.
HealthStatus argoResourceStatus(ArgoResource r) {
  if (r.health == ArgoHealth.degraded || r.health == ArgoHealth.missing) {
    return HealthStatus.failed;
  }
  if (r.sync == ArgoSync.outOfSync || r.requiresPruning) {
    return HealthStatus.warning;
  }
  if (r.sync == ArgoSync.synced && r.health == ArgoHealth.healthy) {
    return HealthStatus.healthy;
  }
  return HealthStatus.unknown;
}
