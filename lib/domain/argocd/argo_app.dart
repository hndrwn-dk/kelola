import 'package:kelola/design/kelola_theme.dart';

/// M49 §2b. Read-only view of Argo CD Applications. Built only by
/// `parseArgoApps`, which keeps the §2c fields out (no Helm or plugin
/// inputs, repo URLs without credentials).

enum ArgoSync { synced, outOfSync, unknown }

enum ArgoHealth { healthy, progressing, degraded, suspended, missing, unknown }

enum ArgoOpPhase { running, succeeded, failed, error, terminating, none }

/// §2d: "not converging" and "progressing too long" both use this.
const kArgoStaleAfter = Duration(minutes: 10);

String argoSyncLabel(ArgoSync s) => switch (s) {
      ArgoSync.synced => 'Synced',
      ArgoSync.outOfSync => 'OutOfSync',
      ArgoSync.unknown => 'Unknown',
    };

String argoHealthLabel(ArgoHealth h) => switch (h) {
      ArgoHealth.healthy => 'Healthy',
      ArgoHealth.progressing => 'Progressing',
      ArgoHealth.degraded => 'Degraded',
      ArgoHealth.suspended => 'Suspended',
      ArgoHealth.missing => 'Missing',
      ArgoHealth.unknown => 'Unknown',
    };

String argoOpPhaseLabel(ArgoOpPhase p) => switch (p) {
      ArgoOpPhase.running => 'Running',
      ArgoOpPhase.succeeded => 'Succeeded',
      ArgoOpPhase.failed => 'Failed',
      ArgoOpPhase.error => 'Error',
      ArgoOpPhase.terminating => 'Terminating',
      ArgoOpPhase.none => 'None',
    };

int _rank(HealthStatus h) => switch (h) {
      HealthStatus.failed => 3,
      HealthStatus.warning => 2,
      HealthStatus.unknown => 1,
      HealthStatus.healthy => 0,
    };

class ArgoSource {
  /// Credentials, query and fragment already stripped.
  final String repoUrl;
  final String? path;
  final String? chart;

  /// `'HEAD'` when the spec leaves it empty.
  final String targetRevision;

  /// `'git'`, `'helm'` or `'oci'`.
  final String kind;

  const ArgoSource({
    required this.repoUrl,
    this.path,
    this.chart,
    this.targetRevision = 'HEAD',
    this.kind = 'git',
  });

  @override
  String toString() => 'ArgoSource(repoUrl: $repoUrl, path: $path, '
      'chart: $chart, targetRevision: $targetRevision, kind: $kind)';
}

class ArgoResource {
  final String group;
  final String kind;
  final String namespace;
  final String name;
  final ArgoSync sync;
  final ArgoHealth health;
  final String? healthMessage;
  final bool requiresPruning;

  const ArgoResource({
    this.group = '',
    this.kind = '',
    this.namespace = '',
    this.name = '',
    this.sync = ArgoSync.unknown,
    this.health = ArgoHealth.unknown,
    this.healthMessage,
    this.requiresPruning = false,
  });

  @override
  String toString() => 'ArgoResource(group: $group, kind: $kind, '
      'namespace: $namespace, name: $name, sync: ${sync.name}, '
      'health: ${health.name}, healthMessage: $healthMessage, '
      'requiresPruning: $requiresPruning)';
}

class ArgoCondition {
  final String type;
  final String message;

  const ArgoCondition({required this.type, this.message = ''});

  @override
  String toString() => 'ArgoCondition(type: $type, message: $message)';
}

class ArgoHistoryEntry {
  final int id;

  /// Already short (see `shortRevision`).
  final String revision;
  final DateTime? deployedAt;

  const ArgoHistoryEntry({
    required this.id,
    required this.revision,
    this.deployedAt,
  });

  @override
  String toString() => 'ArgoHistoryEntry(id: $id, revision: $revision, '
      'deployedAt: ${deployedAt?.toIso8601String()})';
}

class ArgoFinding {
  final HealthStatus health;

  /// The Application name.
  final String subject;
  final String message;

  const ArgoFinding({
    required this.health,
    required this.subject,
    required this.message,
  });

  @override
  String toString() =>
      'ArgoFinding(${health.name}, subject: $subject, message: $message)';
}

class ArgoApp {
  final String name;
  final String namespace;
  final String project;
  final List<ArgoSource> sources;

  /// `destination.server`, or `destination.name` when there's no server.
  final String destServer;
  final String destNamespace;
  final ArgoSync sync;
  final ArgoHealth health;

  /// `status.sync.revisions`, or `[status.sync.revision]`, as read.
  final List<String> syncedRevisions;
  final bool automated;
  final bool prune;
  final bool selfHeal;
  final ArgoOpPhase opPhase;
  final String? opMessage;
  final DateTime? opStartedAt;
  final DateTime? opFinishedAt;
  final List<ArgoCondition> conditions;
  final List<ArgoResource> resources;

  /// Newest first.
  final List<ArgoHistoryEntry> history;
  final DateTime? reconciledAt;

  const ArgoApp({
    required this.name,
    this.namespace = '',
    this.project = '',
    this.sources = const [],
    this.destServer = '',
    this.destNamespace = '',
    this.sync = ArgoSync.unknown,
    this.health = ArgoHealth.unknown,
    this.syncedRevisions = const [],
    this.automated = false,
    this.prune = false,
    this.selfHeal = false,
    this.opPhase = ArgoOpPhase.none,
    this.opMessage,
    this.opStartedAt,
    this.opFinishedAt,
    this.conditions = const [],
    this.resources = const [],
    this.history = const [],
    this.reconciledAt,
  });

  /// First synced revision, short (7 for a commit SHA).
  String? get syncedRevision {
    for (final r in syncedRevisions) {
      if (r.isNotEmpty) {
        return shortArgoRevision(r);
      }
    }
    return null;
  }

  /// `<sync> · <health> · <short revision>`; the revision part is left out
  /// when Argo CD reports none.
  String get rowMeta {
    return [
      argoSyncLabel(sync),
      argoHealthLabel(health),
      ?syncedRevision,
    ].join(' · ');
  }

  /// §2d severity table. Facts (suspended, out of sync while automated sync
  /// is still on it, unknown) produce no finding. Worst first.
  List<ArgoFinding> findings(DateTime now) {
    final out = <ArgoFinding>[];
    void add(HealthStatus h, String message) =>
        out.add(ArgoFinding(health: h, subject: name, message: message));

    bool olderThanStale(DateTime t) =>
        now.toUtc().difference(t.toUtc()) > kArgoStaleAfter;

    switch (health) {
      case ArgoHealth.degraded:
        add(HealthStatus.failed, 'degraded');
      case ArgoHealth.missing:
        add(HealthStatus.failed, 'missing');
      case ArgoHealth.healthy:
      case ArgoHealth.progressing:
      case ArgoHealth.suspended:
      case ArgoHealth.unknown:
        break;
    }
    switch (opPhase) {
      case ArgoOpPhase.failed:
        add(HealthStatus.failed, 'last sync failed');
      case ArgoOpPhase.error:
        add(HealthStatus.failed, 'last sync error');
      case ArgoOpPhase.running:
      case ArgoOpPhase.succeeded:
      case ArgoOpPhase.terminating:
      case ArgoOpPhase.none:
        break;
    }
    for (final c in conditions) {
      if (c.type.endsWith('Error')) {
        add(HealthStatus.failed, c.type);
      }
    }
    if (sync == ArgoSync.outOfSync) {
      if (!automated) {
        add(HealthStatus.warning, 'out of sync');
      } else {
        final r = reconciledAt;
        if (r == null || olderThanStale(r)) {
          add(HealthStatus.warning, 'not converging');
        }
      }
    }
    if (health == ArgoHealth.progressing) {
      final since = opStartedAt ?? reconciledAt;
      if (since != null && olderThanStale(since)) {
        final minutes = now.toUtc().difference(since.toUtc()).inMinutes;
        add(HealthStatus.warning, 'progressing for $minutes min');
      }
    }
    // Stable: failed rows were added before warnings.
    return out;
  }

  /// Worst finding; [HealthStatus.unknown] when Argo CD reports neither sync
  /// nor health and nothing is wrong; healthy otherwise.
  HealthStatus status(DateTime now) {
    final f = findings(now);
    if (f.isNotEmpty) {
      return f.first.health;
    }
    if (sync == ArgoSync.unknown && health == ArgoHealth.unknown) {
      return HealthStatus.unknown;
    }
    return HealthStatus.healthy;
  }

  @override
  String toString() => 'ArgoApp(name: $name, namespace: $namespace, '
      'project: $project, sources: $sources, destServer: $destServer, '
      'destNamespace: $destNamespace, sync: ${sync.name}, '
      'health: ${health.name}, syncedRevisions: $syncedRevisions, '
      'automated: $automated, prune: $prune, selfHeal: $selfHeal, '
      'opPhase: ${opPhase.name}, opMessage: $opMessage, '
      'opStartedAt: ${opStartedAt?.toIso8601String()}, '
      'opFinishedAt: ${opFinishedAt?.toIso8601String()}, '
      'conditions: $conditions, resources: $resources, history: $history, '
      'reconciledAt: ${reconciledAt?.toIso8601String()})';
}

class ArgoApps {
  final List<ArgoApp> apps;

  /// Forbidden / timeout / no kubectl / unreadable output. Never raw stdout.
  final String? error;
  final DateTime readAt;

  /// The probe fell back from the read-only account (owner addition 1).
  final bool readerDenied;

  const ArgoApps({
    required this.apps,
    this.error,
    required this.readAt,
    this.readerDenied = false,
  });

  /// Every Application lives in `openshift-gitops` (slab label decision).
  bool get openShiftGitOps =>
      apps.isNotEmpty && apps.every((a) => a.namespace == 'openshift-gitops');

  int get synced => apps.where((a) => a.sync == ArgoSync.synced).length;

  int get healthy => apps.where((a) => a.health == ArgoHealth.healthy).length;

  int get syncFailed => apps
      .where(
        (a) => a.opPhase == ArgoOpPhase.failed || a.opPhase == ArgoOpPhase.error,
      )
      .length;

  /// All app findings, worst first (stable within a level).
  List<ArgoFinding> findings(DateTime now) {
    final all = [for (final a in apps) ...a.findings(now)];
    final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
    indexed.sort((x, y) {
      final byRank = _rank(y.$2.health).compareTo(_rank(x.$2.health));
      return byRank != 0 ? byRank : x.$1.compareTo(y.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  HealthStatus overall(DateTime now) {
    if (error != null) {
      return HealthStatus.unknown;
    }
    var worst = HealthStatus.healthy;
    var allUnknown = apps.isNotEmpty;
    for (final a in apps) {
      final s = a.status(now);
      if (s != HealthStatus.unknown) {
        allUnknown = false;
        if (_rank(s) > _rank(worst)) {
          worst = s;
        }
      }
    }
    return allUnknown ? HealthStatus.unknown : worst;
  }

  /// Band text: worst finding (`<app>: <message>`), or
  /// `N apps · all synced and healthy`, or `N apps · S synced · H healthy`.
  String summary(DateTime now) {
    final err = error;
    if (err != null) {
      return err;
    }
    final n = apps.length;
    final count = n == 1 ? '1 app' : '$n apps';
    if (n == 0) {
      return count;
    }
    final f = findings(now);
    if (f.isNotEmpty) {
      return '${f.first.subject}: ${f.first.message}';
    }
    if (synced == n && healthy == n) {
      return '$count · all synced and healthy';
    }
    return '$count · $synced synced · $healthy healthy';
  }
}

/// Short form of a revision: a hex commit SHA longer than 7 becomes its
/// first 7 characters; tags, branches and chart versions stay as they are.
String shortArgoRevision(String rev) {
  final r = rev.trim();
  if (r.length > 7 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(r)) {
    return r.substring(0, 7);
  }
  return r;
}
