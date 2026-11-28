import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';

final _now = DateTime.utc(2026, 11, 10, 10);

DateTime _ago(int minutes, [int seconds = 0]) =>
    _now.subtract(Duration(minutes: minutes, seconds: seconds));

ArgoApp _app({
  String name = 'web',
  ArgoSync sync = ArgoSync.synced,
  ArgoHealth health = ArgoHealth.healthy,
  bool automated = false,
  ArgoOpPhase opPhase = ArgoOpPhase.none,
  DateTime? opStartedAt,
  List<ArgoCondition> conditions = const [],
  DateTime? reconciledAt,
}) {
  return ArgoApp(
    name: name,
    namespace: 'argocd',
    project: 'default',
    sync: sync,
    health: health,
    automated: automated,
    opPhase: opPhase,
    opStartedAt: opStartedAt,
    conditions: conditions,
    reconciledAt: reconciledAt ?? _ago(1),
  );
}

void main() {
  test('stale threshold is ten minutes', () {
    expect(kArgoStaleAfter, const Duration(minutes: 10));
  });

  test('healthy and synced has no finding', () {
    final app = _app();
    expect(app.findings(_now), isEmpty);
    expect(app.status(_now), HealthStatus.healthy);
  });

  group('failed', () {
    test('health degraded', () {
      final f = _app(health: ArgoHealth.degraded).findings(_now).single;
      expect(f.health, HealthStatus.failed);
      expect(f.subject, 'web');
      expect(f.message, 'degraded');
    });

    test('health missing', () {
      final app = _app(health: ArgoHealth.missing);
      expect(app.findings(_now).single.health, HealthStatus.failed);
      expect(app.findings(_now).single.message, 'missing');
      expect(app.status(_now), HealthStatus.failed);
    });

    test('last operation failed', () {
      final f = _app(opPhase: ArgoOpPhase.failed).findings(_now).single;
      expect(f.health, HealthStatus.failed);
      expect(f.message, 'last sync failed');
    });

    test('last operation error', () {
      final f = _app(opPhase: ArgoOpPhase.error).findings(_now).single;
      expect(f.health, HealthStatus.failed);
      expect(f.message, 'last sync error');
    });

    test('condition types ending in Error', () {
      for (final type in const [
        'ComparisonError',
        'SyncError',
        'InvalidSpecError',
      ]) {
        final app = _app(
          conditions: [ArgoCondition(type: type, message: 'boom')],
        );
        final f = app.findings(_now).single;
        expect(f.health, HealthStatus.failed, reason: type);
        expect(f.message, type);
      }
    });

    test('a warning condition is not a finding', () {
      final app = _app(
        conditions: const [
          ArgoCondition(type: 'SharedResourceWarning', message: 'x'),
        ],
      );
      expect(app.findings(_now), isEmpty);
    });

    test('succeeded and running operations are not findings', () {
      expect(_app(opPhase: ArgoOpPhase.succeeded).findings(_now), isEmpty);
      expect(
        _app(opPhase: ArgoOpPhase.running, opStartedAt: _ago(2))
            .findings(_now),
        isEmpty,
      );
    });
  });

  group('warning', () {
    test('out of sync with automated off', () {
      final f = _app(sync: ArgoSync.outOfSync).findings(_now).single;
      expect(f.health, HealthStatus.warning);
      expect(f.message, 'out of sync');
    });

    test('out of sync, automated, reconcile at exactly 10:00 is a fact', () {
      final app = _app(
        sync: ArgoSync.outOfSync,
        automated: true,
        reconciledAt: _ago(10),
      );
      expect(app.findings(_now), isEmpty);
      expect(app.status(_now), HealthStatus.healthy);
    });

    test('out of sync, automated, reconcile at 10:01 is not converging', () {
      final f = _app(
        sync: ArgoSync.outOfSync,
        automated: true,
        reconciledAt: _ago(10, 1),
      ).findings(_now).single;
      expect(f.health, HealthStatus.warning);
      expect(f.message, 'not converging');
    });

    test('out of sync, automated, never reconciled is not converging', () {
      final app = ArgoApp(
        name: 'web',
        sync: ArgoSync.outOfSync,
        health: ArgoHealth.healthy,
        automated: true,
      );
      expect(app.findings(_now).single.message, 'not converging');
    });

    test('progressing for exactly 10:00 since opStartedAt is a fact', () {
      final app = _app(
        health: ArgoHealth.progressing,
        opStartedAt: _ago(10),
        reconciledAt: _ago(30),
      );
      expect(app.findings(_now), isEmpty);
    });

    test('progressing for 10:01 since opStartedAt is a warning', () {
      final f = _app(
        health: ArgoHealth.progressing,
        opStartedAt: _ago(10, 1),
        reconciledAt: _ago(1),
      ).findings(_now).single;
      expect(f.health, HealthStatus.warning);
      expect(f.message, 'progressing for 10 min');
    });

    test('progressing falls back to reconciledAt (10:00 vs 10:01)', () {
      expect(
        _app(health: ArgoHealth.progressing, reconciledAt: _ago(10))
            .findings(_now),
        isEmpty,
      );
      final f = _app(health: ArgoHealth.progressing, reconciledAt: _ago(10, 1))
          .findings(_now)
          .single;
      expect(f.health, HealthStatus.warning);
    });

    test('progressing with no timestamp at all is a fact', () {
      const app = ArgoApp(
        name: 'web',
        sync: ArgoSync.synced,
        health: ArgoHealth.progressing,
      );
      expect(app.findings(_now), isEmpty);
    });
  });

  group('facts', () {
    test('suspended is a fact', () {
      final app = _app(health: ArgoHealth.suspended);
      expect(app.findings(_now), isEmpty);
      expect(app.status(_now), HealthStatus.healthy);
    });

    test('out of sync, automated, recent reconcile is a fact', () {
      final app = _app(
        sync: ArgoSync.outOfSync,
        automated: true,
        reconciledAt: _ago(2),
      );
      expect(app.findings(_now), isEmpty);
    });

    test('unknown sync and health is no finding and unknown status', () {
      final app = _app(sync: ArgoSync.unknown, health: ArgoHealth.unknown);
      expect(app.findings(_now), isEmpty);
      expect(app.status(_now), HealthStatus.unknown);
    });

    test('unknown health alone is no finding', () {
      final app = _app(health: ArgoHealth.unknown);
      expect(app.findings(_now), isEmpty);
      expect(app.status(_now), HealthStatus.healthy);
    });
  });

  test('worst finding wins in status', () {
    final app = _app(
      sync: ArgoSync.outOfSync,
      health: ArgoHealth.degraded,
    );
    expect(app.findings(_now), hasLength(2));
    expect(app.findings(_now).first.health, HealthStatus.failed);
    expect(app.status(_now), HealthStatus.failed);
  });

  group('ArgoApps', () {
    ArgoApps apps(List<ArgoApp> list, {String? error}) =>
        ArgoApps(apps: list, error: error, readAt: _now);

    test('counts', () {
      final a = apps([
        _app(name: 'a'),
        _app(name: 'b', sync: ArgoSync.outOfSync),
        _app(name: 'c', health: ArgoHealth.degraded),
        _app(name: 'd', opPhase: ArgoOpPhase.failed),
        _app(name: 'e', opPhase: ArgoOpPhase.error, sync: ArgoSync.unknown),
      ]);
      expect(a.synced, 3);
      expect(a.healthy, 4);
      expect(a.syncFailed, 2);
    });

    test('all synced and healthy summary, pluralised', () {
      expect(
        apps([_app(name: 'a'), _app(name: 'b')]).summary(_now),
        '2 apps · all synced and healthy',
      );
      expect(
        apps([_app(name: 'a')]).summary(_now),
        '1 app · all synced and healthy',
      );
      expect(apps([_app(name: 'a')]).overall(_now), HealthStatus.healthy);
    });

    test('no findings but not all synced and healthy', () {
      final a = apps([
        _app(name: 'a'),
        _app(name: 'b', health: ArgoHealth.suspended),
        _app(
          name: 'c',
          sync: ArgoSync.outOfSync,
          automated: true,
          reconciledAt: _ago(1),
        ),
      ]);
      expect(a.findings(_now), isEmpty);
      expect(a.summary(_now), '3 apps · 2 synced · 2 healthy');
    });

    test('worst finding first in summary and findings', () {
      final a = apps([
        _app(name: 'a', sync: ArgoSync.outOfSync),
        _app(name: 'b', health: ArgoHealth.degraded),
      ]);
      final f = a.findings(_now);
      expect(f.map((x) => x.subject), ['b', 'a']);
      expect(a.summary(_now), 'b: degraded');
      expect(a.overall(_now), HealthStatus.failed);
    });

    test('warning overall', () {
      expect(
        apps([_app(sync: ArgoSync.outOfSync)]).overall(_now),
        HealthStatus.warning,
      );
    });

    test('error makes overall unknown', () {
      final a = apps(const [], error: 'Forbidden');
      expect(a.overall(_now), HealthStatus.unknown);
      expect(a.summary(_now), 'Forbidden');
    });

    test('all apps unknown is unknown overall', () {
      expect(
        apps([_app(sync: ArgoSync.unknown, health: ArgoHealth.unknown)])
            .overall(_now),
        HealthStatus.unknown,
      );
    });

    test('no apps', () {
      final a = apps(const []);
      expect(a.overall(_now), HealthStatus.healthy);
      expect(a.summary(_now), '0 apps');
    });
  });
}
