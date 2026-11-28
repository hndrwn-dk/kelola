import 'package:kelola/domain/argocd/argo_app.dart';

/// State filter on the Argo CD applications list.
enum ArgoAppFilter {
  all('All', 'No applications.'),
  outOfSync('Out of sync', 'No applications out of sync.'),
  degraded('Degraded', 'No degraded applications.'),
  progressing('Progressing', 'No applications progressing.'),
  syncFailed('Sync failed', 'No failed syncs.');

  const ArgoAppFilter(this.label, this.emptyCopy);

  final String label;
  final String emptyCopy;

  bool matches(ArgoApp app) => switch (this) {
        ArgoAppFilter.all => true,
        ArgoAppFilter.outOfSync => app.sync == ArgoSync.outOfSync,
        ArgoAppFilter.degraded => app.health == ArgoHealth.degraded,
        ArgoAppFilter.progressing => app.health == ArgoHealth.progressing,
        ArgoAppFilter.syncFailed => app.opPhase == ArgoOpPhase.failed ||
            app.opPhase == ArgoOpPhase.error,
      };

  int count(Iterable<ArgoApp> apps) => apps.where(matches).length;
}

/// Applications per project, for the project pills.
Map<String, int> argoProjectCounts(Iterable<ArgoApp> apps) {
  final out = <String, int>{};
  for (final a in apps) {
    out[a.project] = (out[a.project] ?? 0) + 1;
  }
  return out;
}
