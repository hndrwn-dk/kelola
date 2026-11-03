import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/bulk_restart.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/screens/k8s_bulk_restart_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/providers.dart';

import 'support/fakes.dart';

K8sWorkload _w(K8sKind kind, String ns, String name) => K8sWorkload(
      kind: kind,
      namespace: ns,
      name: name,
      ready: 1,
      desired: 1,
      health: HealthStatus.healthy,
    );

final _rows = [
  _w(K8sKind.deployment, 'shop', 'web'),
  _w(K8sKind.deployment, 'shop', 'api'),
  _w(K8sKind.statefulSet, 'shop', 'db'),
  _w(K8sKind.pod, 'shop', 'web-abc'),
  _w(K8sKind.job, 'shop', 'migrate'),
  _w(K8sKind.daemonSet, 'kube-system', 'svclb'),
  _w(K8sKind.deployment, 'blog', 'ghost'),
];

final _kubectl = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);

void main() {
  group('domain', () {
    test('namespaces with restartable kinds; kube-* last', () {
      expect(bulkRestartNamespaces(_rows), ['blog', 'shop', 'kube-system']);
    });

    test('candidates are deploy/sts/ds only, kind then name', () {
      expect(
        bulkRestartCandidates(_rows, 'shop').map((w) => w.title),
        ['shop/api', 'shop/web', 'shop/db'],
      );
      expect(bulkRestartCheckedByDefault('shop'), isTrue);
      expect(bulkRestartCheckedByDefault('kube-system'), isFalse);
    });
  });

  group('screens', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late _BulkPool pool;
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      host = await repo.insert(
        alias: 'k3s-01',
        address: '192.168.1.40',
        port: 22,
        username: 'hendra',
      );
      pool = _BulkPool(repository: repo);
    });

    tearDown(() async {
      await db.close();
    });

    Widget app(Widget home, {bool unlocked = true}) {
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(ReadyEnrollment.new),
          entitlementProvider.overrideWithValue(
            FixedEntitlement(unlocked: unlocked),
          ),
        ],
        child: KelolaApp(home: home),
      );
    }

    void tall(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('restarts checked workloads in order; a failure continues',
        (tester) async {
      tall(tester);
      pool.failOn = {'shop/web'};
      await tester.pumpWidget(
        app(
          K8sBulkRestartScreen(
            host: host,
            facts: _kubectl,
            workloads: _rows,
            initialNamespace: 'shop',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('deploy api'), findsOneWidget);
      expect(find.text('sts db'), findsOneWidget);
      expect(find.text('pod web-abc'), findsNothing);
      expect(find.text('job migrate'), findsNothing);
      expect(
        find.textContaining("rollout restart 'deployment/api'"),
        findsOneWidget,
      );
      expect(find.text('Restart 3'), findsOneWidget);

      // Tapping a row toggles it (same pattern as snippet multi-exec).
      expect(find.byType(Checkbox), findsNothing);
      await tester.tap(find.text('sts db'));
      await tester.pump();
      expect(find.text('not selected · 1/1'), findsOneWidget);
      expect(find.text('Restart 2'), findsOneWidget);

      await tester.tap(find.text('Restart 2'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'shop');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(pool.restarted, ['shop/api', 'shop/web']);
      // Only a restart that went through is waited on.
      expect(pool.waited, ['shop/api']);
      expect(find.text('restarted · ready'), findsOneWidget);
      expect(find.text('rollout failed'), findsOneWidget);
      expect(find.text('Restart 2'), findsOneWidget);
    });

    testWidgets('a Deployment and a StatefulSet with one name stay apart',
        (tester) async {
      tall(tester);
      final rows = [
        _w(K8sKind.deployment, 'cache', 'redis'),
        _w(K8sKind.statefulSet, 'cache', 'redis'),
      ];
      pool.failOn = {};
      await tester.pumpWidget(
        app(
          K8sBulkRestartScreen(
            host: host,
            facts: _kubectl,
            workloads: rows,
            initialNamespace: 'cache',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Restart 2'), findsOneWidget);
      await tester.tap(find.text('sts redis'));
      await tester.pump();
      // Only the StatefulSet was unchecked.
      expect(find.text('Restart 1'), findsOneWidget);
      expect(find.text('selected · 1/1'), findsOneWidget);
      expect(find.text('not selected · 1/1'), findsOneWidget);
      await tester.tap(find.text('Restart 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cache');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(pool.restartedKinds, [K8sKind.deployment]);
      expect(find.text('restarted · ready'), findsOneWidget);
    });

    testWidgets('a rollout that is never ready stops the rest of the batch',
        (tester) async {
      tall(tester);
      pool.neverReady = {'shop/api'};
      await tester.pumpWidget(
        app(
          K8sBulkRestartScreen(
            host: host,
            facts: _kubectl,
            workloads: _rows,
            initialNamespace: 'shop',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Restart 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'shop');
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      // api restarted but never got ready: web and db are not touched.
      expect(pool.restarted, ['shop/api']);
      expect(
        find.text('restarted, not ready: timed out waiting for the condition'),
        findsOneWidget,
      );
      expect(
        find.text('skipped: an earlier rollout was not ready'),
        findsNWidgets(2),
      );
    });

    testWidgets('kube-* namespace starts with nothing checked', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        app(
          K8sBulkRestartScreen(
            host: host,
            facts: _kubectl,
            workloads: _rows,
            initialNamespace: 'kube-system',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ds svclb'), findsOneWidget);
      expect(find.text('Restart 0'), findsOneWidget);
    });

    testWidgets('cancelled confirm runs nothing', (tester) async {
      tall(tester);
      await tester.pumpWidget(
        app(
          K8sBulkRestartScreen(
            host: host,
            facts: _kubectl,
            workloads: _rows,
            initialNamespace: 'blog',
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Restart 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pool.restarted, isEmpty);
    });

    testWidgets('workloads screen: locked shows the sheet, runs nothing',
        (tester) async {
      tall(tester);
      pool.inventory = WorkloadInventory(rows: _rows);
      await tester.pumpWidget(
        app(
          WorkloadsScreen(hostId: host.id, factsOverride: _kubectl),
          unlocked: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Restart namespace…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('keeps multi-exec locked'), findsOneWidget);
      expect(find.byType(K8sBulkRestartScreen), findsNothing);
      expect(pool.restarted, isEmpty);
    });

    testWidgets('workloads screen: unlocked opens bulk restart',
        (tester) async {
      tall(tester);
      pool.inventory = WorkloadInventory(rows: _rows);
      await tester.pumpWidget(
        app(WorkloadsScreen(hostId: host.id, factsOverride: _kubectl)),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Restart namespace…'));
      await tester.pumpAndSettle();
      expect(find.byType(K8sBulkRestartScreen), findsOneWidget);
    });
  });
}

class _BulkPool extends SshSessionPool {
  _BulkPool({required super.repository})
      : super(
          signer: NoSshSigner('bulk restart test must not open SSH'),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  WorkloadInventory inventory = const WorkloadInventory(rows: []);
  Set<String> failOn = {};

  /// Workloads whose rollout never becomes ready.
  Set<String> neverReady = {};
  final waited = <String>[];
  final restarted = <String>[];
  final restartedKinds = <K8sKind>[];

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
    List<int>? stdinBytes,
  }) async {
    if (probe is WorkloadListProbe) {
      return inventory as T;
    }
    if (probe is WorkloadRolloutStatusProbe) {
      final status = probe as WorkloadRolloutStatusProbe;
      expect(status.risk, RiskLevel.read);
      waited.add(status.workload.title);
      if (neverReady.contains(status.workload.title)) {
        throw RolloutNotReady('timed out waiting for the condition');
      }
      return null as T;
    }
    if (probe is WorkloadActionProbe) {
      final action = probe as WorkloadActionProbe;
      expect(action.verb, WorkloadVerb.restart);
      expect(scope, ProbeScope.host);
      restarted.add(action.workload.title);
      restartedKinds.add(action.workload.kind);
      if (failOn.contains(action.workload.title)) {
        throw KelolaException('rollout failed');
      }
      return 'restarted' as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

