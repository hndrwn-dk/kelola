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

/// Filter on the resource list of one Argo CD Application.
enum ArgoResourceFilter {
  all('All', 'No resources.'),
  outOfSync('Out of sync', 'No resources out of sync.'),
  degraded('Degraded', 'No degraded resources.'),
  prune('Prune', 'No resources to prune.');

  const ArgoResourceFilter(this.label, this.emptyCopy);

  final String label;
  final String emptyCopy;

  bool matches(ArgoResource r) => switch (this) {
        ArgoResourceFilter.all => true,
        ArgoResourceFilter.outOfSync => r.sync == ArgoSync.outOfSync,
        ArgoResourceFilter.degraded => r.health == ArgoHealth.degraded,
        ArgoResourceFilter.prune => r.requiresPruning,
      };

  int count(Iterable<ArgoResource> resources) =>
      resources.where(matches).length;
}

/// Applications per project, for the project pills.
Map<String, int> argoProjectCounts(Iterable<ArgoApp> apps) {
  final out = <String, int>{};
  for (final a in apps) {
    out[a.project] = (out[a.project] ?? 0) + 1;
  }
  return out;
}
