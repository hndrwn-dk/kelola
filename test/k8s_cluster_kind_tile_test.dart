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
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/kubernetes_home_screen.dart';
import 'package:kelola/providers.dart';

HostFacts _facts(List<String> runtimes) => HostFacts(
      osId: 'rhel',
      osVersionId: '9.4',
      prettyName: 'RHEL 9.4',
      init: InitSystem.systemd,
      systemdVersion: 252,
      pkg: PackageManager.dnf,
      fw: FirewallBackend.none,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
      runtimes: runtimes,
    );

ClusterHealth _cluster(bool? isOpenShift) => ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: isOpenShift,
    );

void main() {
  group('clusterKindLabel / ClusterKindRecord', () {
    test('three states: only true is OpenShift', () {
      expect(clusterKindLabel(true), 'OpenShift');
      expect(clusterKindLabel(false), 'Kubernetes');
      expect(clusterKindLabel(null), 'Kubernetes');
    });

    test('merge stores only a known kind from an API that answered', () {
      final at = DateTime.utc(2026, 11, 3, 12);
      expect(mergeClusterKind(null, _cluster(true), at)!.isOpenShift, isTrue);
      expect(mergeClusterKind(null, _cluster(false), at)!.isOpenShift, isFalse);
      expect(mergeClusterKind(null, _cluster(null), at), isNull);
      // Unreachable API prints OPENSHIFT_NONE (false): not evidence.
      expect(
        mergeClusterKind(
          null,
          const ClusterHealth(
            apiReachable: false,
            controlPlaneReady: 0,
            controlPlaneDesired: 0,
            isOpenShift: false,
          ),
          at,
        ),
        isNull,
      );
    });

    test('expired login parses as unknown, so it never overwrites the kind',
        () {
      final expired = parseClusterHealth(
        [
          '---READYZ---',
          '---READYZ_FAIL---',
          '---NODES---',
          '---OPENSHIFT---',
          '---OPENSHIFT_NONE---',
          '---CONTEXT---',
          'default/api-crc-testing:6443/kubeadmin',
          '---AUTH---',
          'error: You must be logged in to the server (Unauthorized)',
        ].join('\n'),
      );
      expect(expired.authExpired, isTrue);
      expect(expired.isOpenShift, isNull);
      final cached = ClusterKindRecord(
        isOpenShift: true,
        readAt: DateTime.utc(2026, 11, 3, 10),
        kubeContext: 'default/api-crc-testing:6443/kubeadmin',
      );
      final merged =
          mergeClusterKind(cached, expired, DateTime.utc(2026, 11, 3, 12))!;
      expect(merged.isOpenShift, isTrue);
      expect(merged.readAt, cached.readAt);
      expect(merged.label, 'OpenShift');
    });

    test('a different context reads Kubernetes with the age until next read',
        () {
      final cached = ClusterKindRecord(
        isOpenShift: true,
        readAt: DateTime.utc(2026, 11, 3, 10),
        kubeContext: 'crc-admin',
      );
      final now = DateTime.utc(2026, 11, 3, 10, 5);
      // Newer read under another context, kind unknown.
      final switched = mergeClusterKind(
        cached,
        const ClusterHealth(
          apiReachable: true,
          controlPlaneReady: 0,
          controlPlaneDesired: 0,
          kubeContext: 'k3s-lab',
        ),
        now,
      )!;
      expect(switched.contextMatches, isFalse);
      expect(switched.label, 'Kubernetes');
      expect(switched.toolMeta(now), 'cluster · 5m');
      // The next read that knows the kind settles it.
      final next = mergeClusterKind(
        switched,
        const ClusterHealth(
          apiReachable: true,
          controlPlaneReady: 0,
          controlPlaneDesired: 0,
          isOpenShift: true,
          kubeContext: 'k3s-lab',
        ),
        now,
      )!;
      expect(next.contextMatches, isTrue);
      expect(next.label, 'OpenShift');
      expect(next.toolMeta(now), 'cluster');
    });

    test('same or unknown context is not a change', () {
      final cached = ClusterKindRecord(
        isOpenShift: true,
        readAt: DateTime.utc(2026, 11, 3, 10),
        kubeContext: 'crc-admin',
      );
      for (final ctx in ['crc-admin', '']) {
        final m = mergeClusterKind(
          cached,
          ClusterHealth(
            apiReachable: true,
            controlPlaneReady: 0,
            controlPlaneDesired: 0,
            kubeContext: ctx,
          ),
          DateTime.utc(2026, 11, 3, 10, 5),
        )!;
        expect(m.label, 'OpenShift', reason: ctx);
      }
    });

    test('stale keeps the label and adds the age', () {
      final read = ClusterKindRecord(
        isOpenShift: true,
        readAt: DateTime.utc(2026, 11, 3, 10),
      );
      final fresh = DateTime.utc(2026, 11, 3, 10, 14);
      final stale = DateTime.utc(2026, 11, 3, 12);
      expect(read.isStale(fresh), isFalse);
      expect(read.toolMeta(fresh), 'cluster');
      expect(read.isStale(stale), isTrue);
      expect(read.label, 'OpenShift');
      expect(read.toolMeta(stale), 'cluster · 2h');
    });

    test('store round-trip and junk tolerance', () async {
      final dir = await Directory.systemTemp.createTemp('kelola_kind');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/cluster_kind.json');
      final at = DateTime.utc(2026, 11, 3, 12);
      await ClusterKindStore(file)
          .write('h1', ClusterKindRecord(isOpenShift: true, readAt: at));
      await ClusterKindStore(file)
          .write('h2', ClusterKindRecord(isOpenShift: false, readAt: at));
      final again = ClusterKindStore(file);
      expect((await again.read('h1'))!.isOpenShift, isTrue);
      expect((await again.read('h1'))!.readAt, at);
      expect((await again.read('h2'))!.isOpenShift, isFalse);
      expect(await again.read('h3'), isNull);
      await again.write(
        'h1',
        ClusterKindRecord(
          isOpenShift: true,
          readAt: at,
          kubeContext: 'a',
          seenContext: 'b',
        ),
      );
      final ctx = (await ClusterKindStore(file).read('h1'))!;
      expect(ctx.kubeContext, 'a');
      expect(ctx.seenContext, 'b');
      await again.remove('h1');
      expect(await ClusterKindStore(file).read('h1'), isNull);
      expect(await ClusterKindStore(file).read('h2'), isNotNull);
      await file.writeAsString('not json');
      expect(await ClusterKindStore(file).read('h2'), isNull);
    });
  });

  group('dashboard tile', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late _Pool pool;
    late ClusterKindStore kinds;
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      pool = _Pool(repository: repo);
      kinds = ClusterKindStore.memory();
      host = await repo.insert(
        alias: 'bastion',
        address: '192.168.130.1',
        port: 22,
        username: 'hendra',
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> frames(WidgetTester tester, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpDashboard(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            hostRepositoryProvider.overrideWithValue(repo),
            sessionPoolProvider.overrideWithValue(pool),
            homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
            hardwareSignerProvider.overrideWithValue(_BoomSigner()),
            enrollmentProvider.overrideWith(_ReadyEnrollment.new),
            clusterKindStoreProvider.overrideWith((ref) async => kinds),
          ],
          child: KelolaApp(home: HostDashboardScreen(hostId: host.id)),
        ),
      );
      await frames(tester);
    }

    ToolTile tile(WidgetTester tester) => tester.widget<ToolTile>(
          find.byKey(const ValueKey('dashboard-k8s-tile')),
        );

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    for (final (cached, label) in [
      (true, 'OpenShift'),
      (false, 'Kubernetes'),
      (null, 'Kubernetes'),
    ]) {
      testWidgets('isOpenShift $cached → $label, no SSH for the label',
          (tester) async {
        await repo.saveFacts(host.id, _facts(const ['oc']));
        if (cached != null) {
          await kinds.write(
            host.id,
            ClusterKindRecord(
              isOpenShift: cached,
              readAt: DateTime.now().toUtc(),
            ),
          );
        }
        await pumpDashboard(tester);

        expect(tile(tester).label, label);
        expect(tile(tester).meta, 'cluster');
        // Only the dashboard read; the label needed no cluster call.
        expect(pool.probes.map((p) => p.runtimeType), [DashboardProbe]);
        // Still one tile that opens the same Kubernetes home.
        expect(find.byKey(const ValueKey('dashboard-k8s-tile')), findsOneWidget);
        expect(find.text('OpenShift').evaluate().length +
            find.text('Kubernetes').evaluate().length, 1);
        await dispose(tester);
      });
    }

    testWidgets('stale cache keeps OpenShift and shows its age',
        (tester) async {
      await repo.saveFacts(host.id, _facts(const ['oc']));
      await kinds.write(
        host.id,
        ClusterKindRecord(
          isOpenShift: true,
          readAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        ),
      );
      await pumpDashboard(tester);
      expect(tile(tester).label, 'OpenShift');
      expect(tile(tester).meta, 'cluster · 2h');
      await dispose(tester);
    });

    testWidgets('M48.1: OKD version from the home makes the tile read OKD',
        (tester) async {
      await repo.saveFacts(host.id, _facts(const ['oc']));
      // No node image hint: the distro can only come from ClusterVersion.
      pool.cluster = _cluster(true);
      pool.clusterVersion = 'okd/clusterversion_scos.json';
      await pumpDashboard(tester);
      expect(tile(tester).label, 'Kubernetes');

      await tester.tap(find.byKey(const ValueKey('dashboard-k8s-tile')));
      await frames(tester, 20);
      expect(find.text('OKD 4.17.0-OKD-SCOS.0 · STABLE-SCOS-4'), findsOneWidget);
      Navigator.of(tester.element(find.byType(KubernetesHomeScreen))).pop();
      await frames(tester, 20);

      expect(tile(tester).label, 'OKD');
      expect((await kinds.read(host.id))!.distro, OpenShiftDistro.okd);
      await dispose(tester);
    });

    testWidgets('OpenShift context cached → context changes → Kubernetes',
        (tester) async {
      await repo.saveFacts(host.id, _facts(const ['oc']));
      await kinds.write(
        host.id,
        ClusterKindRecord(
          isOpenShift: true,
          readAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          kubeContext: 'default/api-crc-testing:6443/kubeadmin',
        ),
      );
      // The host now reports another context and the kind read is unknown.
      pool.cluster = const ClusterHealth(
        apiReachable: true,
        controlPlaneReady: 1,
        controlPlaneDesired: 1,
        kubeContext: 'k3s-lab',
      );
      await pumpDashboard(tester);
      expect(tile(tester).label, 'OpenShift');

      await tester.tap(find.byKey(const ValueKey('dashboard-k8s-tile')));
      await frames(tester, 20);
      Navigator.of(tester.element(find.byType(KubernetesHomeScreen))).pop();
      await frames(tester, 20);

      expect(tile(tester).label, 'Kubernetes');
      expect(tile(tester).meta, 'cluster · 5m');
      await dispose(tester);
    });

    testWidgets('removing a host forgets its cached kind', (tester) async {
      await kinds.write(
        host.id,
        ClusterKindRecord(isOpenShift: true, readAt: DateTime.now().toUtc()),
      );
      await forgetClusterKind(Future.value(kinds), host.id);
      expect(await kinds.read(host.id), isNull);
      // Never throws, even when the store cannot be opened.
      await forgetClusterKind(Future.error(StateError('no dir')), host.id);
    });

    for (final openShift in [true, false]) {
      testWidgets('tile and band title agree (isOpenShift $openShift)',
          (tester) async {
        await repo.saveFacts(
          host.id,
          _facts(openShift ? const ['oc'] : const ['kubectl']),
        );
        // Seed the opposite so the test proves the home read updates it.
        await kinds.write(
          host.id,
          ClusterKindRecord(
            isOpenShift: !openShift,
            readAt: DateTime.now().toUtc(),
          ),
        );
        pool.cluster = _cluster(openShift);
        await pumpDashboard(tester);

        await tester.tap(find.byKey(const ValueKey('dashboard-k8s-tile')));
        await frames(tester, 20);
        expect(find.byType(KubernetesHomeScreen), findsOneWidget);
        final title = openShift ? 'OPENSHIFT 4.17.3 · STABLE-4.17' : 'KUBERNETES';
        expect(find.text(title), findsOneWidget);

        Navigator.of(tester.element(find.byType(KubernetesHomeScreen))).pop();
        await frames(tester, 20);
        expect(find.byType(KubernetesHomeScreen), findsNothing);
        expect(tile(tester).label, openShift ? 'OpenShift' : 'Kubernetes');
        expect(
          title.toLowerCase(),
          startsWith(tile(tester).label.toLowerCase()),
        );
        await dispose(tester);
      });
    }
  });
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  ClusterHealth cluster = _cluster(false);
  final probes = <Probe<dynamic>>[];

  /// ClusterVersion fixture the OpenShift read returns.
  String clusterVersion = 'synthetic_clusterversion_healthy.json';

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
    if (probe is DashboardProbe) {
      return const DashboardSnapshot(
        uptime: Duration(hours: 1),
        load1: 0.1,
        cpuPercent: 1,
        memUsedPercent: 20,
        diskRootPercent: 40,
        failedUnitCount: 0,
        failedUnitNames: [],
      ) as T;
    }
    if (probe is ClusterHealthProbe) {
      return cluster as T;
    }
    if (probe is WorkloadListProbe) {
      return const WorkloadInventory(rows: []) as T;
    }
    if (probe is ClusterEventsProbe) {
      return const <K8sClusterEvent>[] as T;
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
    if (probe is OpenShiftHealthProbe) {
      return parseOpenShiftHealth(
        [
          '---CLUSTERVERSION---',
          File('test/fixtures/openshift/$clusterVersion').readAsStringSync(),
          '---CLUSTEROPERATORS---',
          '{"items":[]}',
          '---MCP---',
          '{"items":[]}',
          '---CSR---',
          '{"items":[]}',
        ].join('\n'),
      ) as T;
    }
    throw StateError('unexpected probe ${probe.runtimeType}');
  }
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _NoopWidgetBridge implements HomeWidgetBridge {
  const _NoopWidgetBridge();

  @override
  Future<void> write(HomeWidgetSnapshot snap) async {}
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('no key');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('no key');
  }

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) async {}

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
