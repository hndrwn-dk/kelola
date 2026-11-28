import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';

/// M49 §3a: shown under the data when the read-only account could not list
/// Applications and the read fell back to the login's own identity.
const kArgoReaderDeniedCopy =
    "Read-only account can't read Argo CD yet. Re-run setup.";

/// Slab label for the GitOps section: `OpenShift GitOps` when every
/// Application lives in `openshift-gitops`, else `Argo CD` (also unread).
String argoSlabLabel(ArgoApps? apps) =>
    apps != null && apps.openShiftGitOps ? 'OpenShift GitOps' : 'Argo CD';

/// M49 §3a: the GitOps section body on the Kubernetes home, for a read that
/// answered ([ArgoApps.error] is null; the home shows errors itself).
class ArgoGitOpsBlock extends StatelessWidget {
  const ArgoGitOpsBlock({
    super.key,
    required this.apps,
    required this.now,
    required this.onOpenApps,
  });

  final ArgoApps apps;
  final DateTime now;
  final VoidCallback onOpenApps;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final n = apps.apps.length;
    final overall = apps.overall(now);
    final findings = apps.findings(now);
    final failed = apps.syncFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskBand.forHealth(
          status: overall,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                apps.summary(now),
                style: KelolaType.display(
                  color: c.text,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
              if (findings.isNotEmpty) ...[
                const SizedBox(height: 8),
                K8sRows(
                  rows: [
                    for (final f in findings)
                      K8sListRow(
                        name: f.subject,
                        meta: f.message,
                        status: f.health,
                      ),
                  ],
                  limit: 3,
                ),
              ],
              if (apps.readerDenied)
                const K8sQuietNote(
                  kArgoReaderDeniedCopy,
                  key: ValueKey('argo-reader-denied'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                key: const ValueKey('argo-stat-synced'),
                label: 'Synced',
                value: '${apps.synced}/$n',
                meterFraction: n == 0 ? null : apps.synced / n,
                status: n == 0
                    ? null
                    : apps.synced == n
                        ? HealthStatus.healthy
                        : HealthStatus.warning,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatCard(
                key: const ValueKey('argo-stat-healthy'),
                label: 'Healthy',
                value: '${apps.healthy}/$n',
                meterFraction: n == 0 ? null : apps.healthy / n,
                status: n == 0
                    ? null
                    : apps.healthy == n
                        ? HealthStatus.healthy
                        : HealthStatus.warning,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatCard(
                key: const ValueKey('argo-stat-last-sync'),
                label: 'Last sync',
                value: failed > 0 ? 'failed $failed' : 'ok',
                status: n == 0
                    ? null
                    : failed > 0
                        ? HealthStatus.failed
                        : HealthStatus.healthy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ToolTile(
                key: const ValueKey('argo-tool-apps'),
                label: 'Applications',
                meta: n == 1 ? '1 app' : '$n apps',
                status: overall,
                onTap: onOpenApps,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
