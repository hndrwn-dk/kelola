import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/kubernetes_home_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _HomePool pool;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'rocky-lab',
      address: '192.168.1.40',
      port: 22,
      username: 'hendra',
    );
    pool = _HomePool(repository: repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpHome(
    WidgetTester tester, {
    HostFacts? facts,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(
          home: KubernetesHomeScreen(
            hostId: host.id,
            factsOverride: facts ?? HostFacts.undiscovered,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('no kubectl shows honest empty copy', (tester) async {
    await pumpHome(tester);
    expect(find.text(workloadEmptyCopy), findsOneWidget);
    expect(find.text('CLUSTER'), findsNothing);
    expect(pool.probes, isEmpty);
  });

  testWidgets('shows cluster band, worst workloads, and opens All workloads',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      thisHost: ClusterNodeMembership(
        name: 'rocky-lab',
        ready: true,
        kubeletVersion: 'v1.31.0',
        containerRuntime: 'containerd://1.7.22',
        controlPlane: true,
      ),
      thisHostMatched: true,
    );
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'default',
          name: 'api',
          ready: 1,
          desired: 2,
          health: HealthStatus.warning,
        ),
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'default',
          name: 'api-x',
          ready: 0,
          desired: 1,
          phase: 'CrashLoopBackOff',
          health: HealthStatus.failed,
        ),
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'kube-system',
          name: 'coredns-abc',
          ready: 1,
          desired: 1,
          phase: 'Running',
          health: HealthStatus.healthy,
        ),
      ],
    );

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.textContaining('Kubernetes'), findsWidgets);
    expect(find.text('CLUSTER'), findsOneWidget);
    expect(find.text('reachable'), findsOneWidget);
    expect(find.text('1/1 Ready'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.textContaining('Ready · kubelet · containerd'), findsOneWidget);
    expect(find.text('WORKLOADS'), findsOneWidget);
    expect(find.text('default/api-x'), findsOneWidget);
    expect(find.textContaining('CrashLoopBackOff'), findsOneWidget);
    expect(pool.probes.whereType<ClusterHealthProbe>(), hasLength(1));
    expect(pool.probes.whereType<WorkloadListProbe>(), hasLength(1));

    await tester.ensureVisible(find.text('All workloads'));
    await tester.tap(find.text('All workloads'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(WorkloadsScreen), findsOneWidget);
    expect(find.textContaining('Workloads'), findsWidgets);
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _HomePool extends SshSessionPool {
  _HomePool({required super.repository})
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
  WorkloadInventory inventory = const WorkloadInventory(rows: []);
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
      return inventory as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('k8s home test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('k8s home test must not open SSH');
  }

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) async {
    throw StateError('k8s home test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
