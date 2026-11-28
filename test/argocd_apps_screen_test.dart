import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/screens/argo_apps_screen.dart';
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

ArgoApp _app(
  String name, {
  String project = 'default',
  ArgoSync sync = ArgoSync.synced,
  ArgoHealth health = ArgoHealth.healthy,
  ArgoOpPhase op = ArgoOpPhase.none,
}) {
  return ArgoApp(
    name: name,
    namespace: 'argocd',
    project: project,
    sync: sync,
    health: health,
    opPhase: op,
    syncedRevisions: const ['0123456789abcdef'],
  );
}

// 6 apps: 2 out of sync, 1 degraded, 1 progressing, 1 sync failed.
List<ArgoApp> _mixed() => [
      _app('alpha'),
      _app('bravo', sync: ArgoSync.outOfSync),
      _app('charlie', sync: ArgoSync.outOfSync, health: ArgoHealth.degraded),
      _app('delta', health: ArgoHealth.progressing),
      _app('echo', op: ArgoOpPhase.failed),
      _app('foxtrot'),
    ];

Future<void> _pump(
  WidgetTester tester,
  List<ArgoApp> apps, {
  DateTime? readAt,
  void Function(BuildContext, ArgoApp)? onOpenApp,
}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hostsProvider.overrideWith((ref) => Stream.value(const [_host])),
      ],
      child: KelolaApp(
        home: ArgoAppsScreen(
          host: _host,
          facts: HostFacts.undiscovered,
          apps: ArgoApps(apps: apps, readAt: readAt ?? _now),
          workloads: const [],
          readAt: readAt ?? _now,
          now: () => _now,
          onOpenApp: onOpenApp,
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
  testWidgets('every state pill shows its count', (tester) async {
    await _pump(tester, _mixed());
    expect(find.text('ALL 6'), findsOneWidget);
    expect(find.text('OUT OF SYNC 2'), findsOneWidget);
    expect(find.text('DEGRADED 1'), findsOneWidget);
    expect(find.text('PROGRESSING 1'), findsOneWidget);
    expect(find.text('SYNC FAILED 1'), findsOneWidget);
    expect(find.text('Synced · Healthy · 0123456'), findsNWidgets(3));
  });

  testWidgets('state pill filters rows and rows sort worst first',
      (tester) async {
    await _pump(tester, _mixed());
    final order = [
      // delta (progressing, recent) is a neutral fact: after warnings, before
      // the green rows.
      for (final n in ['charlie', 'echo', 'bravo', 'delta', 'alpha', 'foxtrot'])
        tester.getTopLeft(find.text(n)).dy,
    ];
    expect(order, orderedEquals([...order]..sort()));
    await _tapKey(tester, 'argo-filter-outOfSync');
    expect(find.text('bravo'), findsOneWidget);
    expect(find.text('charlie'), findsOneWidget);
    expect(find.text('alpha'), findsNothing);
  });

  testWidgets('each empty state', (tester) async {
    await _pump(tester, [_app('alpha')]);
    await _tapKey(tester, 'argo-filter-outOfSync');
    expect(find.text('No applications out of sync.'), findsOneWidget);
    await _tapKey(tester, 'argo-filter-degraded');
    expect(find.text('No degraded applications.'), findsOneWidget);
    await _tapKey(tester, 'argo-filter-progressing');
    expect(find.text('No applications progressing.'), findsOneWidget);
    await _tapKey(tester, 'argo-filter-syncFailed');
    expect(find.text('No failed syncs.'), findsOneWidget);
    await _pump(tester, const []);
    await _tapKey(tester, 'argo-filter-all');
    expect(find.text('No applications.'), findsOneWidget);
  });

  testWidgets('project pill ANDs with the state pill', (tester) async {
    await _pump(tester, [
      _app('a1', project: 'team-a', sync: ArgoSync.outOfSync),
      _app('a2', project: 'team-a'),
      _app('b1', project: 'team-b', sync: ArgoSync.outOfSync),
      _app('b2', project: 'team-b', sync: ArgoSync.outOfSync),
      _app('b3', project: 'team-b'),
    ]);
    expect(find.text('PROJECT TEAM-A 2'), findsOneWidget);
    expect(find.text('PROJECT TEAM-B 3'), findsOneWidget);
    await _tapKey(tester, 'argo-project-team-b');
    expect(find.text('OUT OF SYNC 2'), findsOneWidget);
    expect(find.text('ALL 2'), findsNothing);
    expect(find.text('ALL 3'), findsOneWidget);
    await _tapKey(tester, 'argo-filter-outOfSync');
    expect(find.text('b1'), findsOneWidget);
    expect(find.text('a1'), findsNothing);
    // Tap again clears the project.
    await _tapKey(tester, 'argo-project-team-b');
    expect(find.text('a1'), findsOneWidget);
    expect(find.text('a2'), findsNothing);
  });

  testWidgets('project with no match shows the state empty copy',
      (tester) async {
    await _pump(tester, [
      _app('a1', project: 'team-a', sync: ArgoSync.outOfSync),
      _app('b1', project: 'team-b'),
    ]);
    await _tapKey(tester, 'argo-project-team-b');
    await _tapKey(tester, 'argo-filter-outOfSync');
    expect(find.text('No applications out of sync.'), findsOneWidget);
  });

  testWidgets('no project pills with a single project', (tester) async {
    await _pump(tester, _mixed());
    expect(find.byKey(const ValueKey('argo-project-default')), findsNothing);
    expect(find.textContaining('PROJECT'), findsNothing);
  });

  testWidgets('age label at 16 min, none at 14 min', (tester) async {
    await _pump(tester, _mixed(),
        readAt: _now.subtract(const Duration(minutes: 16)));
    expect(find.textContaining('as of 16m'), findsOneWidget);
    await _pump(tester, _mixed(),
        readAt: _now.subtract(const Duration(minutes: 14)));
    expect(find.textContaining('as of'), findsNothing);
  });

  testWidgets('rows are tappable only with onOpenApp', (tester) async {
    ArgoApp? opened;
    await _pump(tester, [_app('alpha')],
        onOpenApp: (_, a) => opened = a);
    await tester.tap(find.text('alpha'));
    await tester.pump();
    expect(opened?.name, 'alpha');
  });
}
