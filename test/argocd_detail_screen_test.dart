import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_filters.dart';
import 'package:kelola/domain/argocd/argo_parser.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/presentation/screens/argo_app_detail_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/providers.dart';

final _now = DateTime.utc(2026, 11, 10, 12);

const _host = Host(
  id: 'h1',
  alias: 'lab-k3s',
  address: '10.0.0.5',
  port: 22,
  username: 'hendra',
  keyAlias: 'k',
);

const _web = ArgoResource(
  group: 'apps',
  kind: 'Deployment',
  namespace: 'prod',
  name: 'web',
  sync: ArgoSync.outOfSync,
  health: ArgoHealth.degraded,
  healthMessage: 'ReplicaSet has timed out progressing',
);

const _cfg = ArgoResource(
  kind: 'ConfigMap',
  namespace: 'prod',
  name: 'settings',
  sync: ArgoSync.synced,
  health: ArgoHealth.healthy,
);

const _old = ArgoResource(
  kind: 'Secret',
  namespace: 'prod',
  name: 'stale-creds',
  sync: ArgoSync.outOfSync,
  health: ArgoHealth.unknown,
  requiresPruning: true,
);

ArgoApp _app({
  List<ArgoSource>? sources,
  List<ArgoResource> resources = const [_web, _cfg, _old],
  List<ArgoCondition> conditions = const [],
  bool automated = true,
}) {
  return ArgoApp(
    name: 'shop',
    namespace: 'argocd',
    project: 'default',
    sources: sources ??
        [
          ArgoSource(
            repoUrl: stripRepoCredentials(
              'https://user:tok-SECRET-123@github.com/org/shop.git?t=1#f',
            ),
            path: 'deploy/prod',
            targetRevision: 'main',
          ),
        ],
    destServer: 'https://kubernetes.default.svc',
    destNamespace: 'prod',
    sync: ArgoSync.outOfSync,
    health: ArgoHealth.degraded,
    syncedRevisions: const ['0123456789abcdef'],
    automated: automated,
    prune: automated,
    selfHeal: automated,
    opPhase: ArgoOpPhase.failed,
    opMessage: 'one or more objects failed to apply',
    opStartedAt: _now.subtract(const Duration(minutes: 5)),
    opFinishedAt: _now.subtract(const Duration(minutes: 4)),
    conditions: conditions,
    resources: resources,
    history: [
      ArgoHistoryEntry(
        id: 2,
        revision: 'abcdef1',
        deployedAt: _now.subtract(const Duration(hours: 2)),
      ),
      ArgoHistoryEntry(
        id: 1,
        revision: '1111111',
        deployedAt: _now.subtract(const Duration(days: 3)),
      ),
    ],
    reconciledAt: _now,
  );
}

Future<void> _pump(
  WidgetTester tester,
  ArgoApp app, {
  List<K8sWorkload> workloads = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hostsProvider.overrideWith((ref) => Stream.value(const [_host])),
      ],
      child: KelolaApp(
        home: ArgoAppDetailScreen(
          host: _host,
          facts: HostFacts.undiscovered,
          app: app,
          workloads: workloads,
          readAt: _now,
          now: () => _now,
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
}

void main() {
  testWidgets('source shows the stripped URL and never the token',
      (tester) async {
    await _pump(tester, _app());
    expect(find.text('https://github.com/org/shop.git'), findsOneWidget);
    expect(find.text('deploy/prod'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.text('0123456'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('user:'), findsNothing);
    expect(find.text('SOURCE'), findsOneWidget);
  });

  testWidgets('multi-source apps number their sources', (tester) async {
    await _pump(
      tester,
      _app(sources: const [
        ArgoSource(repoUrl: 'https://a.example/a.git', path: 'a'),
        ArgoSource(
          repoUrl: 'https://charts.example',
          chart: 'nginx',
          targetRevision: '1.2.3',
          kind: 'helm',
        ),
      ]),
    );
    expect(find.text('SOURCE 1'), findsOneWidget);
    expect(find.text('SOURCE 2'), findsOneWidget);
    expect(find.text('nginx'), findsOneWidget);
    expect(find.text('SOURCE'), findsNothing);
  });

  testWidgets('destination, sync policy and last operation', (tester) async {
    await _pump(tester, _app());
    expect(find.text('https://kubernetes.default.svc'), findsOneWidget);
    expect(find.text('prod'), findsWidgets);
    expect(find.text('Automated · prune · self-heal'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('one or more objects failed to apply'), findsOneWidget);
    expect(find.textContaining('2026-11-10T11:55:00'), findsOneWidget);
    await _pump(tester, _app(automated: false));
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('band shows the worst finding and conditions list ComparisonError',
      (tester) async {
    await _pump(
      tester,
      _app(conditions: const [
        ArgoCondition(type: 'ComparisonError', message: 'rpc error: no repo'),
      ]),
    );
    expect(find.text('shop: degraded'), findsOneWidget);
    expect(find.text('ComparisonError'), findsOneWidget);
    expect(find.text('rpc error: no repo'), findsOneWidget);
  });

  testWidgets('healthy app band reads Synced · Healthy', (tester) async {
    await _pump(
      tester,
      const ArgoApp(
        name: 'ok',
        sync: ArgoSync.synced,
        health: ArgoHealth.healthy,
      ),
    );
    expect(find.text('Synced · Healthy'), findsOneWidget);
  });

  testWidgets('resource pills carry counts and filter rows', (tester) async {
    await _pump(tester, _app());
    expect(find.text('ALL 3'), findsOneWidget);
    expect(find.text('OUT OF SYNC 2'), findsOneWidget);
    expect(find.text('DEGRADED 1'), findsOneWidget);
    expect(find.text('PRUNE 1'), findsOneWidget);
    expect(find.text('settings'), findsOneWidget);
    await _tapKey(tester, 'argo-res-prune');
    expect(find.text('stale-creds'), findsOneWidget);
    expect(find.text('settings'), findsNothing);
    await _tapKey(tester, 'argo-res-degraded');
    expect(find.text('web'), findsOneWidget);
    expect(find.text('stale-creds'), findsNothing);
  });

  testWidgets('each resource empty state', (tester) async {
    await _pump(tester, _app(resources: const [_cfg]));
    await _tapKey(tester, 'argo-res-outOfSync');
    expect(find.text('No resources out of sync.'), findsOneWidget);
    await _tapKey(tester, 'argo-res-degraded');
    expect(find.text('No degraded resources.'), findsOneWidget);
    await _tapKey(tester, 'argo-res-prune');
    expect(find.text('No resources to prune.'), findsOneWidget);
    await _pump(tester, _app(resources: const []));
    await _tapKey(tester, 'argo-res-all');
    expect(find.text('No resources.'), findsOneWidget);
  });

  testWidgets('history lists newest first with short revision and age',
      (tester) async {
    await _pump(tester, _app());
    final newest = tester.getTopLeft(find.text('abcdef1')).dy;
    final older = tester.getTopLeft(find.text('1111111')).dy;
    expect(newest, lessThan(older));
    expect(find.text('2h'), findsOneWidget);
    expect(find.text('3d'), findsOneWidget);
  });

  testWidgets('a Deployment with a matching workload opens its detail',
      (tester) async {
    await _pump(
      tester,
      _app(),
      workloads: const [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'prod',
          name: 'web',
          ready: 1,
          desired: 2,
        ),
      ],
    );
    await tester.tap(find.text('web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkloadDetailScreen), findsOneWidget);
  });

  testWidgets('same name in another namespace opens the sheet',
      (tester) async {
    await _pump(
      tester,
      _app(),
      workloads: const [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'staging',
          name: 'web',
          ready: 1,
          desired: 1,
        ),
      ],
    );
    await tester.tap(find.text('web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkloadDetailScreen), findsNothing);
    expect(find.byType(KelolaSheet), findsOneWidget);
  });

  testWidgets('a Deployment from another API group opens the sheet',
      (tester) async {
    await _pump(
      tester,
      _app(resources: const [
        ArgoResource(
          group: 'example.com',
          kind: 'Deployment',
          namespace: 'prod',
          name: 'web',
        ),
      ]),
      workloads: const [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'prod',
          name: 'web',
          ready: 1,
          desired: 1,
        ),
      ],
    );
    await tester.tap(find.text('web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkloadDetailScreen), findsNothing);
    expect(find.byType(KelolaSheet), findsOneWidget);
  });

  testWidgets('a ConfigMap row opens the sheet; a Deployment without a '
      'match does too', (tester) async {
    await _pump(tester, _app());
    await tester.tap(find.text('settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.byType(WorkloadDetailScreen), findsNothing);
    expect(find.text('ConfigMap'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KelolaSheet), findsNothing);
    await tester.tap(find.text('web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.text('ReplicaSet has timed out progressing'), findsOneWidget);
  });

  testWidgets('read-only: no Sync or Refresh anywhere', (tester) async {
    await _pump(tester, _app());
    for (final t in ['Sync', 'Sync with prune', 'Refresh', 'Hard refresh']) {
      expect(find.text(t), findsNothing);
      expect(find.text(t.toUpperCase()), findsNothing);
    }
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  test('ArgoResourceFilter matches and counts', () {
    const all = [_web, _cfg, _old];
    expect(ArgoResourceFilter.all.count(all), 3);
    expect(ArgoResourceFilter.outOfSync.count(all), 2);
    expect(ArgoResourceFilter.degraded.count(all), 1);
    expect(ArgoResourceFilter.prune.count(all), 1);
    expect(ArgoResourceFilter.prune.emptyCopy, 'No resources to prune.');
  });
}
