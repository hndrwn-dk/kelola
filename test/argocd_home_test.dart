import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/k8s_reader_probes.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/argo_app_detail_screen.dart';
import 'package:kelola/presentation/screens/argo_apps_screen.dart';
import 'package:kelola/presentation/screens/kubernetes_home_screen.dart';
import 'package:kelola/presentation/widgets/argo_gitops_block.dart';
import 'package:kelola/providers.dart';

String _fixture(String name) =>
    File('test/fixtures/argocd/$name').readAsStringSync();

String _apps(String name) => '---APPS---\n${_fixture(name)}\n';

final _now = DateTime.utc(2026, 11, 10, 9, 6);

// Plain kubectl, so the home's other reads (reader status) behave as usual.
final _kubectlFacts =
    HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);

ClusterHealth _cluster({bool? argo}) => ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: false,
      hasArgo: argo,
    );

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _ArgoPool pool;
  late Host host;
  late ClusterKindStore kinds;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'lab-k3s',
      address: '10.0.0.5',
      port: 22,
      username: 'hendra',
    );
    pool = _ArgoPool(repository: repo);
    kinds = ClusterKindStore.memory();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
          clusterKindStoreProvider.overrideWith((ref) async => kinds),
        ],
        child: KelolaApp(
          home: KubernetesHomeScreen(
            hostId: host.id,
            factsOverride: _kubectlFacts,
            now: () => _now,
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  void expectOtherSlabs() {
    for (final slab in [
      'KUBERNETES',
      'WORKLOADS',
      'EVENTS',
      'CHANGES',
      'NETWORKING',
      'STORAGE',
      'CONFIGURATION',
      'SECURITY',
    ]) {
      expect(find.text(slab), findsOneWidget, reason: slab);
    }
  }

  void expectNoArgo() {
    expect(pool.probes.whereType<ArgoAppsProbe>(), isEmpty);
    expect(find.text('ARGO CD'), findsNothing);
    expect(find.text('OPENSHIFT GITOPS'), findsNothing);
    expect(find.textContaining('GitOps'), findsNothing);
    expect(find.textContaining('Argo CD'), findsNothing);
    expect(find.byKey(const ValueKey('argo-tool-apps')), findsNothing);
  }

  testWidgets('hasArgo false: no section, no read, other slabs unchanged',
      (tester) async {
    pool.cluster = _cluster(argo: false);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);
    expectNoArgo();
    expectOtherSlabs();
  });

  testWidgets('hasArgo null and nothing cached: hidden', (tester) async {
    pool.cluster = _cluster();
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);
    expectNoArgo();
    expectOtherSlabs();
  });

  testWidgets('hasArgo true + guestbook: slab, band, stat cards, tile',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);

    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));
    expect(find.text('ARGO CD'), findsOneWidget);
    expect(find.text('1 app · all synced and healthy'), findsOneWidget);
    expect(find.text('1 apps · all synced and healthy'), findsNothing);

    final synced = find.byKey(const ValueKey('argo-stat-synced'));
    final healthy = find.byKey(const ValueKey('argo-stat-healthy'));
    final lastSync = find.byKey(const ValueKey('argo-stat-last-sync'));
    expect(synced, findsOneWidget);
    expect(healthy, findsOneWidget);
    expect(lastSync, findsOneWidget);
    expect(tester.widget<StatCard>(synced).label, 'Synced');
    expect(tester.widget<StatCard>(synced).value, '1/1');
    expect(tester.widget<StatCard>(healthy).label, 'Healthy');
    expect(tester.widget<StatCard>(healthy).value, '1/1');
    expect(tester.widget<StatCard>(lastSync).label, 'Last sync');
    expect(tester.widget<StatCard>(lastSync).value, 'ok');

    final tile = find.byKey(const ValueKey('argo-tool-apps'));
    expect(tile, findsOneWidget);
    expect(tester.widget<ToolTile>(tile).label, 'Applications');
    expect(tester.widget<ToolTile>(tile).meta, '1 app');
    expect(find.byKey(const ValueKey('argo-reader-denied')), findsNothing);

    // Placed after the cluster band, before Workloads.
    final argoY = tester.getTopLeft(find.text('ARGO CD')).dy;
    expect(argoY, greaterThan(tester.getTopLeft(find.text('KUBERNETES')).dy));
    expect(argoY, lessThan(tester.getTopLeft(find.text('WORKLOADS')).dy));
    expectOtherSlabs();
  });

  testWidgets('every app in openshift-gitops: OpenShift GitOps slab',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_openshift_gitops.json');
    await pumpHome(tester);
    expect(find.text('OPENSHIFT GITOPS'), findsOneWidget);
    expect(find.text('ARGO CD'), findsNothing);
  });

  testWidgets('forbidden: mono error, no stat cards, no tile',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _fixture('apps_forbidden.txt');
    await pumpHome(tester);

    expect(find.text('ARGO CD'), findsOneWidget);
    final err = find.text('Could not read Argo CD applications: Forbidden');
    expect(err, findsOneWidget);
    final style = tester.widget<Text>(err).style!;
    expect(style.fontFamily, KelolaType.mono(color: Colors.white).fontFamily);
    expect(find.byKey(const ValueKey('argo-stat-synced')), findsNothing);
    expect(find.byKey(const ValueKey('argo-stat-healthy')), findsNothing);
    expect(find.byKey(const ValueKey('argo-stat-last-sync')), findsNothing);
    expect(find.byKey(const ValueKey('argo-tool-apps')), findsNothing);
  });

  testWidgets('tapping Applications pushes ArgoAppsScreen', (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('argo-tool-apps')));
    await tester.pumpAndSettle();
    expect(find.byType(ArgoAppsScreen), findsOneWidget);
    expect(find.text('guestbook'), findsWidgets);
  });

  testWidgets('cached true + fresh null: shown', (tester) async {
    await kinds.write(
      host.id,
      ClusterKindRecord(
        isOpenShift: false,
        readAt: _now.subtract(const Duration(hours: 1)),
        hasArgo: true,
      ),
    );
    pool.cluster = _cluster();
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);

    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));
    expect(find.text('ARGO CD'), findsOneWidget);
    expect(find.text('1 app · all synced and healthy'), findsOneWidget);
  });

  testWidgets('cached true from another context + fresh null: hidden',
      (tester) async {
    await kinds.write(
      host.id,
      ClusterKindRecord(
        isOpenShift: false,
        readAt: _now.subtract(const Duration(hours: 1)),
        kubeContext: 'lab-a',
        hasArgo: true,
      ),
    );
    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: false,
      kubeContext: 'lab-b',
    );
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);
    expectNoArgo();
  });

  testWidgets('cached true + fresh false: hidden', (tester) async {
    await kinds.write(
      host.id,
      ClusterKindRecord(
        isOpenShift: false,
        readAt: _now.subtract(const Duration(hours: 1)),
        hasArgo: true,
      ),
    );
    pool.cluster = _cluster(argo: false);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);
    expectNoArgo();
  });

  testWidgets('reader denied + guestbook: data and the reader-denied line',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout =
        '---READER_DENIED---\n${_apps('apps_guestbook_synced.json')}';
    await pumpHome(tester);

    expect(find.text('1 app · all synced and healthy'), findsOneWidget);
    expect(find.byKey(const ValueKey('argo-stat-synced')), findsOneWidget);
    final note = find.byKey(const ValueKey('argo-reader-denied'));
    expect(note, findsOneWidget);
    expect(
      find.text("Read-only account can't read Argo CD yet. Re-run setup."),
      findsOneWidget,
    );
    expect(
      kArgoReaderDeniedCopy,
      "Read-only account can't read Argo CD yet. Re-run setup.",
    );
  });

  testWidgets('forbidden + reader denied: error only, no line',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout =
        '---READER_DENIED---\n${_fixture('apps_forbidden.txt')}';
    await pumpHome(tester);

    expect(
      find.text('Could not read Argo CD applications: Forbidden'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('argo-reader-denied')), findsNothing);
    expect(find.text(kArgoReaderDeniedCopy), findsNothing);
    expect(find.byKey(const ValueKey('argo-stat-synced')), findsNothing);
  });

  Future<void> refresh(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Refresh'));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  Future<void> cacheArgo() => kinds.write(
        host.id,
        ClusterKindRecord(
          isOpenShift: false,
          readAt: _now.subtract(const Duration(hours: 1)),
          hasArgo: true,
        ),
      );

  testWidgets('refresh true then false hides the section and its apps',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    await pumpHome(tester);
    expect(find.text('ARGO CD'), findsOneWidget);

    pool.cluster = _cluster(argo: false);
    await refresh(tester);
    expect(find.text('ARGO CD'), findsNothing);
    expect(find.byKey(const ValueKey('argo-tool-apps')), findsNothing);
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));
    expect(find.text('1 app · all synced and healthy'), findsNothing);
  });

  testWidgets('a late cache-path result from an older load is dropped',
      (tester) async {
    await cacheArgo();
    pool.cluster = _cluster();
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    pool.argoGate = Completer<void>();
    await pumpHome(tester);
    expect(find.text('ARGO CD'), findsOneWidget);
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));

    // The next load says no Argo CD; then the old read finishes.
    pool.cluster = _cluster(argo: false);
    await refresh(tester);
    expect(find.text('ARGO CD'), findsNothing);
    pool.argoGate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.text('ARGO CD'), findsNothing);
    expect(find.text('1 app · all synced and healthy'), findsNothing);
    expect(find.byKey(const ValueKey('argo-tool-apps')), findsNothing);
  });

  testWidgets('a refresh while a cache-path read is pending reuses it',
      (tester) async {
    await cacheArgo();
    pool.cluster = _cluster();
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    pool.argoGate = Completer<void>();
    await pumpHome(tester);
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));

    await refresh(tester);
    // Unknown fresh answer: the section stays up while the cache answers.
    expect(find.text('ARGO CD'), findsOneWidget);
    expect(pool.probes.whereType<ClusterHealthProbe>(), hasLength(2));
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));

    pool.argoGate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));
    expect(find.text('1 app · all synced and healthy'), findsOneWidget);
  });

  testWidgets('band text is mono; a finding row opens that app',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_degraded.json');
    await pumpHome(tester);

    final band = find.textContaining('bad-image: ');
    expect(band, findsOneWidget);
    expect(tester.widget<Text>(band).style?.fontFamily, 'IBMPlexMono');

    final row = find.descendant(
      of: find.byType(ArgoGitOpsBlock),
      matching: find.text('bad-image'),
    );
    expect(row, findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    final detail = tester.widget<ArgoAppDetailScreen>(
      find.byType(ArgoAppDetailScreen),
    );
    expect(detail.app.name, 'bad-image');
    expect(detail.readAt, _now);
  });

  testWidgets('a slow fresh Argo read does not hold back the other sections',
      (tester) async {
    pool.cluster = _cluster(argo: true);
    pool.argoStdout = _apps('apps_guestbook_synced.json');
    pool.events = const [
      K8sClusterEvent(
        namespace: 'prod',
        type: 'Warning',
        reason: 'BackOff',
        message: 'Back-off restarting failed container',
        objectKind: 'Pod',
        objectName: 'web-1',
      ),
    ];
    pool.argoGate = Completer<void>();
    await pumpHome(tester);

    // Events (Wave 2) and the reader check are in while Argo CD still reads.
    expect(find.text('BackOff'), findsOneWidget);
    expect(pool.probes.whereType<K8sReaderStatusProbe>(), hasLength(1));
    expect(find.text('ARGO CD'), findsOneWidget);
    expect(find.text('1 app · all synced and healthy'), findsNothing);

    // A refresh meanwhile joins the pending read instead of a second one.
    await refresh(tester);
    expect(pool.probes.whereType<ClusterHealthProbe>(), hasLength(2));
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));

    pool.argoGate!.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.text('1 app · all synced and healthy'), findsOneWidget);
    expect(pool.probes.whereType<ArgoAppsProbe>(), hasLength(1));
  });

  group('argoSlabLabel', () {
    test('Argo CD by default and while unread', () {
      expect(argoSlabLabel(null), 'Argo CD');
    });
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _ArgoPool extends SshSessionPool {
  _ArgoPool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  ClusterHealth cluster = const ClusterHealth(
    apiReachable: false,
    controlPlaneReady: 0,
    controlPlaneDesired: 0,
  );

  /// What ArgoAppsProbe's command prints; parsed by the real probe.
  String argoStdout = '';

  /// When set, ArgoAppsProbe waits on it (a slow Applications read).
  Completer<void>? argoGate;

  List<K8sClusterEvent> events = const [];
  final probes = <Probe<dynamic>>[];

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
    probes.add(probe);
    if (probe is ClusterHealthProbe) {
      return cluster as T;
    }
    if (probe is WorkloadListProbe) {
      return const WorkloadInventory(rows: []) as T;
    }
    if (probe is ClusterEventsProbe) {
      return events as T;
    }
    if (probe is ServiceListProbe) {
      return const K8sNetworking(services: []) as T;
    }
    if (probe is StorageListProbe) {
      return const K8sStorage(claims: [], volumes: []) as T;
    }
    if (probe is ConfigInventoryProbe) {
      return const K8sConfigInventory() as T;
    }
    if (probe is SecurityInventoryProbe) {
      return const K8sSecurityInventory() as T;
    }
    if (probe is RolloutHistoryProbe) {
      return const <K8sRevision>[] as T;
    }
    if (probe is ArgoAppsProbe) {
      await argoGate?.future;
      return ArgoAppsProbe(now: () => _now).parse(argoStdout, '', 0) as T;
    }
    // Reader status and anything else: a failed section, never a crash.
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('argo home test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('argo home test must not open SSH');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {
    throw StateError('argo home test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
