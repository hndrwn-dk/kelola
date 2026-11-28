import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_parser.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/fleet/fleet_k8s_read.dart';

String _fixture(String name) =>
    File('test/fixtures/argocd/$name').readAsStringSync();

final _readAt = DateTime.utc(2026, 11, 10, 9, 6);

final _kubectl = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);

const _healthyK8s = FleetK8sSummary(
  read: true,
  apiReachable: true,
  nodesReady: 3,
  nodesTotal: 3,
);

FleetHostHealth _host(FleetK8sSummary? k8s) => FleetHostHealth(
      hostId: 'h1',
      alias: 'bastion',
      reachable: true,
      load1: 0.1,
      nprocCores: 4,
      memPercent: 20,
      diskRootPercent: 30,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.now().toUtc(),
      k8s: k8s,
    );

/// Cluster read output; [argo] is the ARGO_CRD section (null = no section).
String _clusterOut({String? argo}) => [
      '---HOSTNAME---',
      'bastion',
      '---READYZ---',
      'ok',
      '---NODES---',
      '{"items":[]}',
      '---OPENSHIFT---',
      '---OPENSHIFT_NONE---',
      if (argo != null) ...['---ARGO_CRD---', argo],
    ].join('\n');

ArgoApps _apps(List<ArgoApp> apps) => ArgoApps(apps: apps, readAt: _readAt);

class _Runner {
  _Runner({this.hasArgo, this.argoFails = false});

  final bool? hasArgo;
  final bool argoFails;
  final ran = <Type>[];

  Future<T> call<T>(Probe<T> probe) async {
    ran.add(probe.runtimeType);
    if (probe is FleetClusterProbe) {
      return probe.parse(
        _clusterOut(
          argo: hasArgo == null
              ? null
              : (hasArgo!
                  ? 'customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io'
                  : ''),
        ),
        '',
        0,
      );
    }
    if (probe is FleetWorkloadListProbe) {
      return const WorkloadInventory(rows: []) as T;
    }
    if (probe is FleetArgoProbe) {
      if (argoFails) {
        throw StateError('forbidden');
      }
      return _apps(const [
        ArgoApp(
          name: 'a',
          sync: ArgoSync.outOfSync,
          health: ArgoHealth.degraded,
          opPhase: ArgoOpPhase.failed,
        ),
        ArgoApp(name: 'b', sync: ArgoSync.synced, health: ArgoHealth.healthy),
      ]) as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

void main() {
  group('FleetArgoSummary', () {
    test('from counts apps, out of sync, degraded and sync failed', () {
      final s = FleetArgoSummary.from(
        _apps(const [
          ArgoApp(
            name: 'a',
            sync: ArgoSync.outOfSync,
            health: ArgoHealth.degraded,
            opPhase: ArgoOpPhase.failed,
          ),
          ArgoApp(
            name: 'b',
            sync: ArgoSync.outOfSync,
            health: ArgoHealth.missing,
            opPhase: ArgoOpPhase.error,
          ),
          ArgoApp(name: 'c', sync: ArgoSync.synced, health: ArgoHealth.healthy),
        ]),
      );
      expect(s.apps, 3);
      expect(s.outOfSync, 2);
      expect(s.degraded, 2);
      expect(s.syncFailed, 2);
    });

    test('tileLine omits zero parts', () {
      expect(const FleetArgoSummary(apps: 12).tileLine, 'Argo 12 · ok');
      expect(
        const FleetArgoSummary(
          apps: 12,
          outOfSync: 2,
          degraded: 1,
          syncFailed: 1,
        ).tileLine,
        'Argo 12 · 2 out of sync · 1 degraded · 1 sync failed',
      );
      expect(
        const FleetArgoSummary(apps: 3, degraded: 1).tileLine,
        'Argo 3 · 1 degraded',
      );
    });

    test('tileValue: sync failed, then degraded, then out of sync, then ok', () {
      expect(
        const FleetArgoSummary(
          apps: 9,
          outOfSync: 2,
          degraded: 1,
          syncFailed: 1,
        ).tileValue,
        '1 fail',
      );
      expect(
        const FleetArgoSummary(apps: 9, outOfSync: 2, degraded: 1).tileValue,
        '1 deg',
      );
      expect(const FleetArgoSummary(apps: 9, outOfSync: 2).tileValue, '2 oos');
      expect(const FleetArgoSummary(apps: 9).tileValue, 'ok');
    });

    test('health: failed, warning, healthy', () {
      expect(
        const FleetArgoSummary(apps: 1, syncFailed: 1).health,
        HealthStatus.failed,
      );
      expect(
        const FleetArgoSummary(apps: 1, degraded: 1).health,
        HealthStatus.failed,
      );
      expect(
        const FleetArgoSummary(apps: 1, outOfSync: 1).health,
        HealthStatus.warning,
      );
      expect(const FleetArgoSummary(apps: 1).health, HealthStatus.healthy);
    });

    test('JSON round trip and key names', () {
      const s = FleetArgoSummary(
        apps: 12,
        outOfSync: 2,
        degraded: 1,
        syncFailed: 1,
      );
      expect(s.toJson(), {'n': 12, 'oos': 2, 'deg': 1, 'fail': 1});
      final back = FleetArgoSummary.fromJson(s.toJson())!;
      expect(back.toJson(), s.toJson());
      expect(FleetArgoSummary.fromJson(null), isNull);
      expect(FleetArgoSummary.fromJson('x'), isNull);
    });

    test('survives the fleet cache JSON; old JSON has no argo', () {
      final s = _healthyK8s.withArgo(
        const FleetArgoSummary(apps: 4, outOfSync: 1),
      );
      final round = FleetK8sSummary.decode(s.encode())!;
      expect(round.argo!.toJson(), s.argo!.toJson());
      expect(round.nodesTotal, 3);
      final old = FleetK8sSummary.decode(
        '{"read":true,"api":true,"nodesReady":1,"nodesTotal":1,"failed":0,"warn":0}',
      )!;
      expect(old.argo, isNull);
    });

    test('withNodes and withOcp carry argo', () {
      final s = _healthyK8s.withArgo(const FleetArgoSummary(apps: 4));
      expect(s.withNodes(const ['n1']).argo, isNotNull);
      expect(s.withOcp(null).argo, isNotNull);
      expect(s.withOcp(const FleetOcpSummary()).argo!.apps, 4);
    });

    test('helm-secrets fixture leaves no secret in the summary JSON', () {
      final r = parseArgoApps(
        '---APPS---\n${_fixture('apps_helm_secrets.json')}\n',
        readAt: _readAt,
      );
      expect(r.error, isNull);
      final json = jsonEncode(FleetArgoSummary.from(r).toJson());
      const secrets = [
        's3cr3t-helm-value',
        'p4ram-secret',
        'plugin-env-secret',
        'kustomize-patch-secret',
        'info-secret',
        'fp-secret-file',
        'jsonnet-ext-secret',
        'jsonnet-tla-secret',
      ];
      for (final s in secrets) {
        expect(json, isNot(contains(s)));
      }
      expect(json, contains('"n":2'));
    });
  });

  group('readFleetK8s Argo step', () {
    test('hasArgo true: FleetArgoProbe runs and the summary has argo',
        () async {
      final run = _Runner(hasArgo: true);
      final s = await readFleetK8s(_kubectl, run.call);
      expect(run.ran, contains(FleetArgoProbe));
      expect(s!.argo, isNotNull);
      expect(s.argo!.apps, 2);
      expect(s.argo!.outOfSync, 1);
      expect(s.argo!.syncFailed, 1);
    });

    test('hasArgo false: probe never runs', () async {
      final run = _Runner(hasArgo: false);
      final s = await readFleetK8s(_kubectl, run.call, cachedHasArgo: () async => true);
      expect(run.ran, isNot(contains(FleetArgoProbe)));
      expect(s!.argo, isNull);
    });

    test('hasArgo null and cached null: probe never runs', () async {
      final run = _Runner();
      final s = await readFleetK8s(_kubectl, run.call);
      expect(run.ran, isNot(contains(FleetArgoProbe)));
      expect(s!.argo, isNull);
    });

    test('hasArgo null and cached false: probe never runs', () async {
      final run = _Runner();
      await readFleetK8s(_kubectl, run.call, cachedHasArgo: () async => false);
      expect(run.ran, isNot(contains(FleetArgoProbe)));
    });

    test('hasArgo null and cached true: probe runs', () async {
      final run = _Runner();
      final s = await readFleetK8s(_kubectl, run.call, cachedHasArgo: () async => true);
      expect(run.ran, contains(FleetArgoProbe));
      expect(s!.argo, isNotNull);
    });

    test('cached flag is asked only when fresh hasArgo is null', () async {
      var asked = 0;
      Future<bool?> cached() async {
        asked++;
        return true;
      }

      await readFleetK8s(_kubectl, _Runner(hasArgo: true).call,
          cachedHasArgo: cached);
      await readFleetK8s(_kubectl, _Runner(hasArgo: false).call,
          cachedHasArgo: cached);
      expect(asked, 0);
      await readFleetK8s(_kubectl, _Runner().call, cachedHasArgo: cached);
      expect(asked, 1);
    });

    test('cached flag is never asked without kubectl', () async {
      var asked = 0;
      final s = await readFleetK8s(
        HostFacts.undiscovered,
        _Runner().call,
        cachedHasArgo: () async {
          asked++;
          return true;
        },
      );
      expect(s, isNull);
      expect(asked, 0);
    });

    test('cached flag throwing is treated as unknown', () async {
      final run = _Runner();
      final s = await readFleetK8s(
        _kubectl,
        run.call,
        cachedHasArgo: () async => throw StateError('disk'),
      );
      expect(run.ran, isNot(contains(FleetArgoProbe)));
      expect(s!.read, isTrue);
    });

    test('Argo probe throwing leaves argo null and keeps the rest', () async {
      final run = _Runner(hasArgo: true, argoFails: true);
      final s = await readFleetK8s(_kubectl, run.call);
      expect(run.ran, contains(FleetArgoProbe));
      expect(s!.argo, isNull);
      expect(s.read, isTrue);
    });
  });

  group('tile', () {
    String? cell(FleetK8sSummary? k) {
      final m = _host(k).tileMetrics().where((m) => m.label == 'argo');
      return m.isEmpty ? null : m.single.value;
    }

    test('argo cell shows the short value', () {
      expect(
        cell(_healthyK8s.withArgo(const FleetArgoSummary(apps: 3))),
        'ok',
      );
      expect(
        cell(
          _healthyK8s.withArgo(const FleetArgoSummary(apps: 3, syncFailed: 1)),
        ),
        '1 fail',
      );
    });

    test('no argo cell without argo, and no fleet issue for Argo', () {
      expect(cell(_healthyK8s), isNull);
      expect(cell(null), isNull);
      final a = assessFleetHost(
        _host(
          _healthyK8s.withArgo(
            const FleetArgoSummary(apps: 3, degraded: 1, syncFailed: 1),
          ),
        ),
      );
      expect(a.issues, isEmpty);
    });

    test('argo cell comes after the ocp cell', () {
      final labels = _host(
        _healthyK8s
            .withOcp(const FleetOcpSummary(version: '4.17.3'))
            .withArgo(const FleetArgoSummary(apps: 3)),
      ).tileMetrics().map((m) => m.label).toList();
      expect(labels.indexOf('argo'), greaterThan(labels.indexOf('ocp')));
    });
  });
}
