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
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _WorkloadPool pool;
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
    pool = _WorkloadPool(repository: repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpWorkloads(
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
          home: WorkloadsScreen(
            hostId: host.id,
            factsOverride: facts ?? HostFacts.undiscovered,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('no kubectl shows honest empty copy and does not list',
      (tester) async {
    await pumpWorkloads(tester);
    expect(find.text(workloadEmptyCopy), findsOneWidget);
    expect(find.byType(ServiceRow), findsNothing);
    expect(pool.probes, isEmpty);
  });

  testWidgets('lists ServiceRows from the inventory probe', (tester) async {
    pool.inventory = const WorkloadInventory(
      rows: [
        K8sWorkload(
          kind: K8sKind.deployment,
          namespace: 'prod',
          name: 'web',
          ready: 2,
          desired: 3,
          health: HealthStatus.warning,
        ),
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'kube-system',
          name: 'coredns',
          ready: 1,
          desired: 1,
          phase: 'Running',
          health: HealthStatus.healthy,
        ),
      ],
    );
    await pumpWorkloads(
      tester,
      facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
    );

    expect(find.text('prod/web'), findsOneWidget);
    expect(find.textContaining('deploy · 2/3'), findsOneWidget);
    expect(find.text('kube-system/coredns'), findsOneWidget);
    expect(pool.probes, [isA<WorkloadListProbe>()]);
  });

  testWidgets('detail shows describe, events, and top as read rows',
      (tester) async {
    pool.describe = 'Name: web\nReplicas: 3';
    pool.events = const [
      K8sEvent(
        type: 'Warning',
        reason: 'Unhealthy',
        message: 'Readiness probe failed',
        when: '2026-09-27T01:00:00Z',
      ),
    ];
    pool.top = const [K8sTopRow(name: 'web-abc', cpu: '12m', memory: '64Mi')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          enrollmentProvider.overrideWith(_ReadyEnrollment.new),
        ],
        child: KelolaApp(
          home: WorkloadDetailScreen(
            host: host,
            facts: HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
            workload: const K8sWorkload(
              kind: K8sKind.deployment,
              namespace: 'prod',
              name: 'web',
              ready: 2,
              desired: 3,
              health: HealthStatus.warning,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Name: web'), findsOneWidget);
    expect(find.text('Unhealthy'), findsOneWidget);
    expect(find.text('Readiness probe failed'), findsOneWidget);
    expect(find.text('web-abc'), findsOneWidget);
    expect(find.text('12m · 64Mi'), findsOneWidget);
    expect(pool.probes, [
      isA<WorkloadDescribeProbe>(),
      isA<WorkloadEventsProbe>(),
      isA<WorkloadTopProbe>(),
    ]);
    expect(pool.scopes, everyElement(ProbeScope.host));
  });

  test('workloads UI never re-detects kubectl or uses fleet', () {
    final list = File('lib/presentation/screens/workloads_screen.dart')
        .readAsStringSync();
    final detail = File('lib/presentation/screens/workload_detail_screen.dart')
        .readAsStringSync();
    final probes = File('lib/domain/probes/workload_probes.dart')
        .readAsStringSync();
    expect(list, contains('HostFactsProbe'));
    expect(list, isNot(contains('command -v')));
    expect(detail, isNot(contains('command -v')));
    expect(probes, isNot(contains('command -v')));
    expect(list, isNot(contains('ProbeScope.fleet')));
    expect(detail, isNot(contains('ProbeScope.fleet')));
    expect(probes, isNot(contains('ProbeScope.fleet')));
  });
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _WorkloadPool extends SshSessionPool {
  _WorkloadPool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(8),
        );

  WorkloadInventory inventory = const WorkloadInventory(rows: []);
  String describe = '';
  List<K8sEvent> events = const [];
  List<K8sTopRow> top = const [];
  final probes = <Probe<dynamic>>[];
  final scopes = <ProbeScope>[];

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
  }) async {
    probes.add(probe);
    scopes.add(scope);
    if (probe is WorkloadListProbe) {
      return inventory as T;
    }
    if (probe is WorkloadDescribeProbe) {
      return describe as T;
    }
    if (probe is WorkloadEventsProbe) {
      return events as T;
    }
    if (probe is WorkloadTopProbe) {
      return top as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('workloads screen test must not open SSH');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('workloads screen test must not open SSH');
  }

  @override
  Future<void> confirmPresence({String reason = 'Confirm destructive action'}) async {
    throw StateError('workloads screen test must not open SSH');
  }

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
