import 'dart:async';
import 'dart:io';
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
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/kubernetes_home_screen.dart';
import 'package:kelola/presentation/widgets/ocp_operator_sheet.dart';
import 'package:kelola/providers.dart';

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

final _ocFacts = HostFacts.undiscovered.copyWith(runtimes: const ['oc']);

ClusterHealth _openShiftCluster() {
  return parseClusterHealth(
    [
      '---HOSTNAME---',
      'bastion',
      '---READYZ---',
      'ok',
      '---NODES---',
      _fixture('synthetic_nodes.json'),
      '---OPENSHIFT---',
      _fixture('synthetic_config_openshift_io_v1.json'),
      '---AUTH---',
    ].join('\n'),
  );
}

OpenShiftHealth _ocp({String? cv, String? csr}) {
  return parseOpenShiftHealth(
    [
      '---CLUSTERVERSION---',
      cv ?? _fixture('synthetic_clusterversion_healthy.json'),
      '---CLUSTEROPERATORS---',
      _fixture('synthetic_clusteroperators.json'),
      '---MCP---',
      _fixture('synthetic_machineconfigpools.json'),
      '---CSR---',
      csr ?? _fixture('synthetic_csr_two_pending.json'),
    ].join('\n'),
  );
}

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _OcpPool pool;
  late Host host;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    host = await repo.insert(
      alias: 'crc-bastion',
      address: '192.168.130.1',
      port: 22,
      username: 'hendra',
    );
    pool = _OcpPool(repository: repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpHome(WidgetTester tester, {HostFacts? facts}) async {
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
        ],
        child: KelolaApp(
          home: KubernetesHomeScreen(
            hostId: host.id,
            factsOverride: facts ?? _ocFacts,
            now: () => DateTime.utc(2026, 11, 3, 12),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
  }

  testWidgets('OpenShift band title, stat cards, chips and DNS label',
      (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocp = _ocp();
    await pumpHome(tester);

    expect(pool.probes.whereType<OpenShiftHealthProbe>(), hasLength(1));
    expect(find.text('OPENSHIFT 4.17.3 · STABLE-4.17'), findsOneWidget);
    expect(find.text('OPENSHIFT'), findsOneWidget); // section slab
    expect(find.text('KUBERNETES'), findsNothing);
    expect(find.text('DNS'), findsOneWidget);
    expect(find.text('CoreDNS'), findsNothing);

    // Summary band: the worst signals, in order.
    expect(
      find.text(
        '1 operator degraded · 1 operator unavailable · 1 pool degraded · '
        '1 node degraded · 1 pool paused · 2 CSRs pending',
      ),
      findsOneWidget,
    );

    // Stat cards.
    expect(find.text('3/5 healthy', findRichText: true), findsOneWidget);
    expect(find.text('2/4 updated', findRichText: true), findsOneWidget);
    expect(find.text('2 pending', findRichText: true), findsOneWidget);

    // Chips with counts.
    expect(find.text('ALL 5'), findsOneWidget);
    expect(find.text('DEGRADED 1'), findsOneWidget);
    expect(find.text('UNAVAILABLE 1'), findsOneWidget);
    expect(find.text('PROGRESSING 1'), findsOneWidget);

    // Node roles + MCD state are on the All nodes list.
    await tester.tap(find.text('All nodes'));
    await tester.pumpAndSettle();
    expect(find.byType(K8sResourceListScreen), findsOneWidget);
    expect(find.text('master, control-plane · Ready · Done'), findsOneWidget);
    expect(
      find.text('worker, infra · Ready · Working (update pending)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Ready · Degraded: unexpected on-disk state'),
      findsOneWidget,
    );
  });

  testWidgets('operator filter chips narrow rows and show empty states',
      (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocp = _ocp();
    await pumpHome(tester);

    // Findings in the band name both; the operator rows follow the chip.
    expect(find.text('authentication'), findsNWidgets(2));
    expect(find.text('ingress'), findsNWidgets(2));
    expect(find.text('dns'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ocp-filter-degraded')));
    await tester.pump();
    expect(find.text('authentication'), findsNWidgets(2));
    expect(find.text('ingress'), findsOneWidget);
    expect(find.text('dns'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ocp-filter-unavailable')));
    await tester.pump();
    expect(find.text('ingress'), findsNWidgets(2));
    expect(find.text('authentication'), findsOneWidget);
  });

  testWidgets('healthy operators: every chip but All is empty',
      (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocp = parseOpenShiftHealth(
      [
        '---CLUSTERVERSION---',
        _fixture('synthetic_clusterversion_healthy.json'),
        '---CLUSTEROPERATORS---',
        '{"items":[{"metadata":{"name":"dns"},"status":{"conditions":[{"type":"Available","status":"True"},{"type":"Degraded","status":"False"}]}}]}',
        '---MCP---',
        '{"items":[]}',
        '---CSR---',
        '{"items":[]}',
      ].join('\n'),
    );
    pool.cluster = parseClusterHealth(
      '---NODES---\n{"items":[]}\n---OPENSHIFT---\n'
      '${_fixture('synthetic_config_openshift_io_v1.json')}\n---READYZ---\nok',
    );
    await pumpHome(tester);
    expect(find.text('ALL 1'), findsOneWidget);
    expect(find.text('DEGRADED 0'), findsOneWidget);
    for (final f in [
      OcpOperatorFilter.degraded,
      OcpOperatorFilter.unavailable,
      OcpOperatorFilter.progressing,
    ]) {
      await tester.tap(find.byKey(ValueKey('ocp-filter-${f.name}')));
      await tester.pump();
      expect(find.text(f.emptyCopy), findsOneWidget, reason: f.name);
    }
    expect(find.text('Operators, pools and nodes healthy'), findsOneWidget);
  });

  testWidgets('operator row opens a read-only sheet with mono conditions',
      (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocp = _ocp();
    await pumpHome(tester);

    await tester.tap(find.byKey(const ValueKey('ocp-filter-degraded')));
    await tester.pump();
    await tester.tap(find.text('authentication').last);
    await tester.pumpAndSettle();

    final sheet = find.byType(OcpOperatorSheetBody);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('OAuthServerRouteEndpointAccessibleController_SyncError')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('as of')),
      findsOneWidget,
    );
    for (final type in ['Available', 'Progressing', 'Degraded']) {
      expect(find.descendant(of: sheet, matching: find.text(type)), findsOneWidget);
    }
    // No action buttons: Close only.
    expect(find.descendant(of: sheet, matching: find.byType(FilledButton)), findsNothing);
    expect(find.byTooltip('Close'), findsOneWidget);
  });

  testWidgets('pool row opens the nodes that pool selects', (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocp = _ocp();
    await pumpHome(tester);

    await tester.tap(find.text('pool worker'));
    await tester.pumpAndSettle();
    expect(find.byType(K8sResourceListScreen), findsOneWidget);
    expect(find.text('worker-1'), findsOneWidget);
    expect(find.text('worker-2'), findsOneWidget);
    expect(find.text('master-0'), findsNothing);
  });

  testWidgets('title reads OpenShift until the version arrives; '
      'section errors show in their card', (tester) async {
    pool.cluster = _openShiftCluster();
    const forbidden =
        'KELOLA_ERR Error from server (Forbidden): forbidden: User "developer" cannot get';
    pool.ocp = _ocp(cv: forbidden, csr: forbidden);
    await pumpHome(tester);

    expect(find.text('OPENSHIFT'), findsNWidgets(2)); // band title + section
    expect(find.text('Could not read CSRs: Forbidden'), findsOneWidget);
    expect(find.text('Could not read cluster version: Forbidden'), findsOneWidget);
    expect(find.text('unknown', findRichText: true), findsWidgets);
  });

  testWidgets('whole OpenShift read failing shows only in its section',
      (tester) async {
    pool.cluster = _openShiftCluster();
    pool.ocpFails = true;
    await pumpHome(tester);

    expect(find.text('Could not read OpenShift health: forbidden'), findsOneWidget);
    expect(find.text('OPENSHIFT'), findsNWidgets(2));
    expect(find.text('No warning events'), findsOneWidget);
  });

  testWidgets('auth expired hides every section', (tester) async {
    pool.cluster = parseClusterHealth(
      [
        '---HOSTNAME---',
        'bastion',
        '---READYZ---',
        '---READYZ_FAIL---',
        '---NODES---',
        '---OPENSHIFT---',
        '---OPENSHIFT_NONE---',
        '---AUTH---',
        'error: You must be logged in to the server (Unauthorized)',
      ].join('\n'),
    );
    await pumpHome(tester);

    final copy = find.byKey(const ValueKey('k8s-auth-expired'));
    expect(copy, findsOneWidget);
    final rich = tester.widget<Text>(copy).textSpan!.toPlainText();
    expect(
      rich,
      'Session on this host expired. Run oc login there, then pull to refresh.',
    );
    for (final slab in [
      'KUBERNETES',
      'OPENSHIFT',
      'WORKLOADS',
      'EVENTS',
      'CHANGES',
      'NETWORKING',
      'STORAGE',
      'CONFIGURATION',
      'SECURITY',
    ]) {
      expect(find.text(slab), findsNothing, reason: slab);
    }
    expect(find.text('unreachable'), findsNothing);
    expect(find.textContaining('session expired'), findsOneWidget);
    // Nothing after the cluster read ran.
    expect(pool.probes.map((p) => p.runtimeType), [ClusterHealthProbe]);
  });

  group('M48.1 OKD', () {
    String okd(String name) => _fixture('okd/$name');

    ClusterHealth okdCluster() => parseClusterHealth(
          [
            '---HOSTNAME---',
            'crc',
            '---READYZ---',
            'ok',
            '---NODES---',
            okd('nodes_scos.json'),
            '---OPENSHIFT---',
            _fixture('synthetic_config_openshift_io_v1.json'),
            '---AUTH---',
          ].join('\n'),
        );

    testWidgets('OKD band title and section slab', (tester) async {
      pool.cluster = okdCluster();
      pool.ocp = _ocp(cv: okd('clusterversion_scos.json'));
      await pumpHome(tester);

      expect(find.text('OKD 4.17.0-OKD-SCOS.0 · STABLE-SCOS-4'), findsOneWidget);
      expect(find.text('OKD'), findsOneWidget); // section slab
      expect(find.text('OPENSHIFT'), findsNothing);
      expect(find.textContaining('OPENSHIFT 4'), findsNothing);
    });

    testWidgets('only nodes read (OpenShift health pending): title OKD',
        (tester) async {
      pool.cluster = okdCluster();
      pool.ocp = _ocp(cv: okd('clusterversion_scos.json'));
      pool.ocpGate = Completer<void>();
      await pumpHome(tester);

      expect(find.text('OKD'), findsNWidgets(2)); // band title + section slab
      expect(find.text('OPENSHIFT'), findsNothing);
      pool.ocpGate!.complete();
      await tester.pump();
      await tester.pump();
    });

    testWidgets('RHCOS fixtures: title unchanged', (tester) async {
      pool.cluster = _openShiftCluster();
      pool.ocp = _ocp();
      await pumpHome(tester);
      expect(find.text('OPENSHIFT 4.17.3 · STABLE-4.17'), findsOneWidget);
      expect(find.text('OPENSHIFT'), findsOneWidget);
      expect(find.text('OKD'), findsNothing);
    });
  });

  testWidgets('vanilla cluster runs no OpenShift read and shows no section',
      (tester) async {
    pool.cluster = const ClusterHealth(
      apiReachable: true,
      controlPlaneReady: 1,
      controlPlaneDesired: 1,
      isOpenShift: false,
    );
    await pumpHome(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );
    expect(pool.probes.whereType<OpenShiftHealthProbe>(), isEmpty);
    expect(find.text('KUBERNETES'), findsOneWidget);
    expect(find.text('OPENSHIFT'), findsNothing);
    expect(find.text('CoreDNS'), findsOneWidget);
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _OcpPool extends SshSessionPool {
  _OcpPool({required super.repository})
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
  OpenShiftHealth ocp = const OpenShiftHealth();
  bool ocpFails = false;

  /// When set, OpenShiftHealthProbe waits on it (health still pending).
  Completer<void>? ocpGate;
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
      await ocpGate?.future;
      if (ocpFails) {
        throw K8sReadException('OpenShift health', 'forbidden');
      }
      return ocp as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('test must not open SSH');
  }

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) async {
    throw StateError('test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
