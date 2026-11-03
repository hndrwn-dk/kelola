import 'dart:async';
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
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_config.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/k8s_resource_detail_screen.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/kubernetes_home_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
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
            now: () => _now,
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
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
      nodes: [
        ClusterNodeMembership(
          name: 'rocky-lab',
          ready: true,
          kubeletVersion: 'v1.31.0',
          containerRuntime: 'containerd://1.7.22',
          controlPlane: true,
        ),
        ClusterNodeMembership(
          name: 'worker-1',
          ready: false,
          kubeletVersion: 'v1.31.0',
          containerRuntime: 'containerd://1.7.22',
          pressures: ['DiskPressure'],
        ),
      ],
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
          restarts: 14,
          podPhase: 'Running',
        ),
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'batch',
          name: 'report-done',
          ready: 0,
          desired: 1,
          phase: 'Succeeded',
          health: HealthStatus.healthy,
          podPhase: 'Succeeded',
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
    expect(
      find.text('Ready · kubelet v1.31.0 · containerd 1.7.22'),
      findsOneWidget,
    );
    expect(find.text('1/2 Ready'), findsOneWidget);
    expect(find.text('worker-1'), findsOneWidget);
    expect(find.text('worker-1: DiskPressure'), findsOneWidget);
    // FilterPill uppercases labels. Succeeded pod is not "not ready":
    // deploy api + pod api-x only.
    expect(find.text('2 NOT READY'), findsOneWidget);
    expect(find.text('1 CRASHLOOP'), findsOneWidget);
    expect(find.text('1 RESTARTING'), findsOneWidget);
    expect(find.text('default/report-done'), findsNothing);
    expect(find.textContaining('14 restarts'), findsOneWidget);
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

  testWidgets('wave 2: events open the workload, services and storage flag problems',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'shop',
          name: 'api-7f9',
          ready: 0,
          desired: 1,
          phase: 'CrashLoopBackOff',
          health: HealthStatus.failed,
          podPhase: 'Running',
        ),
      ],
    );
    pool.events = [
      K8sClusterEvent(
        namespace: 'shop',
        type: 'Warning',
        reason: 'BackOff',
        message: 'Back-off restarting failed container api',
        objectKind: 'Pod',
        objectName: 'api-7f9',
        count: 12,
        at: _now.subtract(const Duration(minutes: 5)),
      ),
      K8sClusterEvent(
        namespace: 'shop',
        type: 'Warning',
        reason: 'FailedMount',
        message: 'MountVolume.SetUp failed',
        objectKind: 'Pod',
        objectName: 'gone-pod',
        at: _now.subtract(const Duration(hours: 3)),
      ),
    ];
    pool.networking = const K8sNetworking(
      services: [
        K8sService(
          namespace: 'shop',
          name: 'api',
          type: 'ClusterIP',
          clusterIp: '10.43.0.10',
          ports: '80/TCP',
          hasSelector: true,
        ),
        K8sService(
          namespace: 'shop',
          name: 'web',
          type: 'ClusterIP',
          clusterIp: '10.43.0.11',
          ports: '80/TCP',
          hasSelector: true,
          readyEndpoints: 2,
        ),
      ],
    );
    pool.storage = const K8sStorage(
      claims: [
        K8sVolumeClaim(
          namespace: 'shop',
          name: 'data',
          phase: 'Pending',
          requested: '10Gi',
          storageClass: 'local-path',
        ),
      ],
      volumes: [],
    );

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.text('EVENTS'), findsOneWidget);
    expect(find.text('2 WARNINGS'), findsOneWidget);
    expect(find.text('1 LAST HOUR'), findsOneWidget);
    expect(find.text('BackOff'), findsOneWidget);
    expect(find.text('Pod shop/api-7f9 · 12× · 5m'), findsOneWidget);
    expect(find.text('Back-off restarting failed container api'), findsOneWidget);

    expect(find.text('NETWORKING'), findsOneWidget);
    expect(find.text('2 SVC'), findsOneWidget);
    expect(find.text('1 NO ENDPOINTS'), findsOneWidget);
    expect(find.text('shop/api'), findsOneWidget);
    expect(find.text('shop/web'), findsNothing);

    expect(find.text('STORAGE'), findsOneWidget);
    expect(find.text('1 PENDING'), findsOneWidget);
    expect(find.text('shop/data'), findsOneWidget);
    expect(find.text('pvc · Pending · 10Gi · local-path'), findsOneWidget);

    expect(pool.probes.whereType<ClusterEventsProbe>(), hasLength(1));
    expect(pool.probes.whereType<ServiceListProbe>(), hasLength(1));
    expect(pool.probes.whereType<StorageListProbe>(), hasLength(1));

    await tester.ensureVisible(find.text('All services'));
    await tester.tap(find.text('All services'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(K8sResourceListScreen), findsOneWidget);
    expect(find.text('shop/web'), findsOneWidget);
    await tester.tap(find.text('PROBLEMS 1'));
    await tester.pump();
    expect(find.text('shop/web'), findsNothing);
    Navigator.of(tester.element(find.byType(K8sResourceListScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Event whose object is a known workload opens its detail (logs/events).
    final eventRow = find.text('BackOff');
    await tester.ensureVisible(eventRow);
    await tester.tap(eventRow);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WorkloadDetailScreen), findsOneWidget);
  });

  testWidgets('detail: service, claim, and volume drill down from the snapshot',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'shop',
          name: 'web-a',
          ready: 1,
          desired: 1,
          phase: 'Running',
          health: HealthStatus.healthy,
          podPhase: 'Running',
          config: K8sPodConfig(claims: ['data']),
        ),
      ],
    );
    pool.networking = const K8sNetworking(
      services: [
        K8sService(
          namespace: 'shop',
          name: 'web',
          type: 'NodePort',
          clusterIp: '10.43.0.11',
          ports: '80:30080/TCP',
          hasSelector: true,
          readyEndpoints: 1,
          notReadyEndpoints: 1,
          selector: {'app': 'web'},
          portList: [
            K8sServicePort(port: 80, nodePort: 30080, targetPort: '8080'),
          ],
          addresses: [
            K8sEndpointAddress(
              ip: '10.42.0.5',
              ready: true,
              nodeName: 'node01',
              targetKind: 'Pod',
              targetNamespace: 'shop',
              targetName: 'web-a',
            ),
            K8sEndpointAddress(ip: '10.42.0.9', ready: false),
          ],
        ),
      ],
    );
    pool.storage = const K8sStorage(
      claims: [
        K8sVolumeClaim(
          namespace: 'shop',
          name: 'data',
          phase: 'Bound',
          capacity: '10Gi',
          storageClass: 'local-path',
          volumeName: 'pvc-123',
          accessModes: ['ReadWriteOnce'],
        ),
        K8sVolumeClaim(
          namespace: 'shop',
          name: 'orphan',
          phase: 'Bound',
          volumeName: 'gone-pv',
        ),
      ],
      volumes: [
        K8sPersistentVolume(
          name: 'pvc-123',
          phase: 'Bound',
          capacity: '10Gi',
          claim: 'shop/data',
          reclaimPolicy: 'Delete',
        ),
      ],
    );

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );
    final probesBefore = pool.probes.length;

    Future<void> settle() async {
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void back(Type screen) {
      Navigator.of(tester.element(find.byType(screen).last)).pop();
    }

    // Routes underneath stay in the tree; look only at the top screen.
    Finder on(Type screen, String text) => find.descendant(
          of: find.byType(screen).last,
          matching: find.text(text),
        );

    // Service: not-ready endpoint makes it a home problem row.
    await tester.ensureVisible(find.text('shop/web'));
    await tester.tap(find.text('shop/web'));
    await settle();
    expect(find.byType(K8sServiceDetailScreen), findsOneWidget);
    expect(find.textContaining('as of 0s ago'), findsOneWidget);
    expect(find.text('app=web'), findsOneWidget);
    expect(find.text('80:30080/TCP → 8080'), findsOneWidget);
    expect(find.text('ready · 10.42.0.5 · node01'), findsOneWidget);
    expect(find.text('not ready'), findsOneWidget, reason: 'no targetRef: IP row');
    // Endpoint pod opens the workload screen.
    await tester.tap(find.text('web-a'));
    await settle();
    expect(find.byType(WorkloadDetailScreen), findsOneWidget);
    back(WorkloadDetailScreen);
    await settle();
    back(K8sServiceDetailScreen);
    await settle();

    // Claim: via All volumes. Shows the bound PV and the mounting pod.
    await tester.ensureVisible(find.text('All volumes'));
    await tester.tap(find.text('All volumes'));
    await settle();
    await tester.tap(on(K8sResourceListScreen, 'shop/data'));
    await settle();
    expect(find.byType(K8sClaimDetailScreen), findsOneWidget);
    expect(on(K8sClaimDetailScreen, 'RWO'), findsOneWidget);
    expect(on(K8sClaimDetailScreen, 'web-a'), findsOneWidget,
        reason: 'mounted by');
    await tester.tap(on(K8sClaimDetailScreen, 'pvc-123'));
    await settle();
    expect(find.byType(K8sVolumeDetailScreen), findsOneWidget);
    expect(on(K8sVolumeDetailScreen, 'Delete'), findsOneWidget);
    // PV links back to its claim.
    await tester.tap(on(K8sVolumeDetailScreen, 'shop/data'));
    await settle();
    expect(find.byType(K8sClaimDetailScreen, skipOffstage: false),
        findsNWidgets(2), reason: 'claim → pv → claim stack');
    back(K8sClaimDetailScreen);
    await settle();
    back(K8sVolumeDetailScreen);
    await settle();
    back(K8sClaimDetailScreen);
    await settle();

    // A bound PV missing from the snapshot is shown, not tappable.
    await tester.tap(on(K8sResourceListScreen, 'shop/orphan'));
    await settle();
    expect(on(K8sClaimDetailScreen, 'not in this snapshot'), findsOneWidget);
    await tester.tap(on(K8sClaimDetailScreen, 'gone-pv'));
    await settle();
    expect(find.byType(K8sVolumeDetailScreen), findsNothing);
    expect(on(K8sClaimDetailScreen, 'Not mounted by any pod.'), findsOneWidget);

    // The workload screen opened from an endpoint reads its own logs and
    // events; the detail screens themselves never re-run a home probe.
    expect(pool.probes.length, greaterThanOrEqualTo(probesBefore));
    expect(pool.probes.whereType<ServiceListProbe>(), hasLength(1));
    expect(pool.probes.whereType<StorageListProbe>(), hasLength(1));
    expect(pool.probes.whereType<WorkloadListProbe>(), hasLength(1));
  });

  testWidgets('pull-to-refresh during a load does not start a second batch',
      (tester) async {
    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.clusterGate = Completer<void>();
    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    // Two pulls while the first load is still waiting on the cluster.
    unawaited(refresh.onRefresh());
    unawaited(refresh.onRefresh());
    await tester.pump();
    pool.clusterGate!.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(pool.probes.whereType<ClusterHealthProbe>(), hasLength(1));
    expect(pool.probes.whereType<ServiceListProbe>(), hasLength(1));
  });

  testWidgets('wave 2: one denied section does not hide the others',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.denyServices = true;

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.text('Could not read services: forbidden'), findsOneWidget);
    // kubectl's own text is server output, so mono.
    expect(
      tester
          .widget<Text>(find.text('Could not read services: forbidden'))
          .style
          ?.fontFamily,
      contains('IBMPlexMono'),
    );
    expect(find.text('No warning events'), findsOneWidget);
    expect(find.text('All claims bound'), findsOneWidget);
  });

  testWidgets('wave 3: configuration and security findings', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'shop',
          name: 'api',
          ready: 0,
          desired: 1,
          health: HealthStatus.failed,
          config: K8sPodConfig(
            containers: [
              K8sContainerConfig(
                name: 'api',
                image: 'ghcr.io/acme/api:1.4.2',
                cpuRequest: '100m',
                memoryRequest: '128Mi',
                memoryLimit: '256Mi',
                readinessProbe: true,
              ),
            ],
            refs: [
              K8sConfigRef(kind: 'Secret', name: 'api-db'),
              K8sConfigRef(kind: 'ConfigMap', name: 'api-env'),
            ],
          ),
        ),
        K8sWorkload(
          kind: K8sKind.daemonSet,
          namespace: 'shop',
          name: 'agent',
          ready: 1,
          desired: 1,
          health: HealthStatus.healthy,
          config: K8sPodConfig(
            containers: [
              K8sContainerConfig(
                name: 'agent',
                image: 'acme/agent',
                privileged: true,
              ),
            ],
            hostNetwork: true,
          ),
        ),
      ],
    );
    pool.config = const K8sConfigInventory(
      configMaps: {
        'shop': {'api-env'},
      },
      secrets: [],
    );
    pool.security = const K8sSecurityInventory(
      serviceAccounts: 4,
      clusterAdminGrants: [(binding: 'ops-admin', subject: 'User alice')],
    );

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.text('CONFIGURATION'), findsOneWidget);
    expect(find.text('1 CM'), findsOneWidget);
    expect(find.text('0 SECRETS'), findsOneWidget);
    expect(find.text('1 MISSING REF'), findsOneWidget);
    expect(find.text('1 HYGIENE'), findsOneWidget);
    expect(find.text('missing Secret api-db'), findsOneWidget);
    expect(find.text('no requests: agent'), findsOneWidget);

    expect(find.text('SECURITY'), findsOneWidget);
    expect(find.text('4 SA'), findsOneWidget);
    expect(find.text('1 CLUSTER-ADMIN'), findsOneWidget);
    expect(find.text('privileged: agent'), findsOneWidget);
    expect(find.text('ds shop/agent'), findsWidgets);
    expect(find.text('namespace shop'), findsOneWidget);

    await tester.ensureVisible(find.text('All security findings'));
    await tester.tap(find.text('All security findings'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(K8sResourceListScreen), findsOneWidget);
    // Scope to the list: the home route underneath can still be on stage
    // while the page transition runs, and it shows the same row.
    final list = find.byType(K8sResourceListScreen);
    expect(
      find.descendant(of: list, matching: find.text('ClusterRoleBinding ops-admin')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.text('cluster-admin → User alice')),
      findsOneWidget,
    );
  });

  testWidgets('wave 4: changes list rollouts and open the workload history',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'shop',
          name: 'web',
          ready: 1,
          desired: 3,
          health: HealthStatus.warning,
        ),
      ],
    );
    pool.history = [
      K8sRevision(
        ownerKind: K8sKind.deployment,
        namespace: 'shop',
        ownerName: 'web',
        revision: 4,
        createdAt: _now.subtract(const Duration(minutes: 12)),
        changes: const ['web nginx:1.25 → nginx:1.27'],
        changeCause: 'bump nginx',
        current: true,
      ),
      K8sRevision(
        ownerKind: K8sKind.deployment,
        namespace: 'shop',
        ownerName: 'web',
        revision: 3,
        createdAt: _now.subtract(const Duration(days: 3)),
        changes: const ['oldest kept'],
      ),
      K8sRevision(
        ownerKind: K8sKind.daemonSet,
        namespace: 'gone',
        ownerName: 'agent',
        revision: 1,
        createdAt: _now.subtract(const Duration(days: 5)),
        changes: const ['created'],
        current: true,
      ),
    ];

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.text('CHANGES'), findsOneWidget);
    expect(find.text('3 REVISIONS'), findsOneWidget);
    expect(find.text('1 LAST 24H'), findsOneWidget);
    expect(find.text('1 ON UNHEALTHY'), findsOneWidget);
    expect(find.text('rev 4 · current · 12m'), findsOneWidget);
    expect(find.text('web nginx:1.25 → nginx:1.27\nbump nginx'), findsOneWidget);

    // A revision whose owner is not in the snapshot is not tappable.
    final orphan = tester.widget<ServiceRow>(
      find.ancestor(
        of: find.text('ds gone/agent'),
        matching: find.byType(ServiceRow),
      ),
    );
    expect(orphan.onTap, isNull);

    await tester.ensureVisible(find.text('rev 4 · current · 12m'));
    await tester.tap(find.text('rev 4 · current · 12m'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(WorkloadDetailScreen), findsOneWidget);
    final detail = find.byType(WorkloadDetailScreen);
    expect(
      find.descendant(of: detail, matching: find.text('HISTORY')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detail,
        matching: find.text('Last 2 revisions kept by the cluster'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('revision 4')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('revision 3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text('revision 1')),
      findsNothing,
    );
    final scoped = pool.probes.whereType<RolloutHistoryProbe>().toList();
    expect(scoped.map((p) => p.namespace), [null, 'shop']);
  });

  testWidgets('wave 4: denied history shows only in its section',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
    );
    pool.denyHistory = true;

    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(
      find.text('Could not read rollout history: forbidden'),
      findsOneWidget,
    );
    expect(find.text('No warning events'), findsOneWidget);
    expect(find.text('All claims bound'), findsOneWidget);
  });
}

final _now = DateTime.utc(2026, 11, 2, 12);

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
  List<K8sClusterEvent> events = const [];
  K8sNetworking networking = const K8sNetworking(services: []);
  K8sStorage storage = const K8sStorage(claims: [], volumes: []);
  K8sConfigInventory config = const K8sConfigInventory();
  K8sSecurityInventory security = const K8sSecurityInventory();
  List<K8sRevision> history = const [];

  /// When set, RolloutHistoryProbe fails like an RBAC-denied kubectl get.
  bool denyHistory = false;

  /// When set, ServiceListProbe fails like an RBAC-denied kubectl get.
  bool denyServices = false;

  /// When set, ClusterHealthProbe waits on it (a slow cluster).
  Completer<void>? clusterGate;
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
      await clusterGate?.future;
      return cluster as T;
    }
    if (probe is WorkloadListProbe) {
      return inventory as T;
    }
    if (probe is ClusterEventsProbe) {
      return events as T;
    }
    if (probe is ServiceListProbe) {
      if (denyServices) {
        throw K8sReadException('services', 'forbidden');
      }
      return networking as T;
    }
    if (probe is StorageListProbe) {
      return storage as T;
    }
    if (probe is ConfigInventoryProbe) {
      return config as T;
    }
    if (probe is SecurityInventoryProbe) {
      return security as T;
    }
    if (probe is RolloutHistoryProbe) {
      if (denyHistory) {
        throw K8sReadException('rollout history', 'forbidden');
      }
      return history as T;
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
