import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/hosts/coreos_ack_store.dart';
import 'package:kelola/data/k8s/cluster_kind_store.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/vault/vault_store.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';
import 'package:kelola/domain/probes/coreos_node_probe.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/vault/vault.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/widgets/coreos_notice_sheet.dart';
import 'package:kelola/providers.dart';

const _rhcos = HostFacts(
  osId: 'rhcos',
  osVersionId: '4.17',
  prettyName: 'Red Hat Enterprise Linux CoreOS 417.94',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.unknown,
  fw: FirewallBackend.none,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _NodePool pool;
  late CoreOsAckStore acks;
  late Host node;
  late Host bastion;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    pool = _NodePool(repository: repo);
    acks = CoreOsAckStore.memory();
    bastion = await repo.insert(
      alias: 'crc-bastion',
      address: '192.168.130.1',
      port: 22,
      username: 'hendra',
    );
    node = await repo.insert(
      alias: 'crc-node',
      address: '192.168.130.11',
      port: 22,
      username: 'core',
    );
    await repo.saveFacts(node.id, _rhcos);
    await repo.saveFleetCache(
      FleetHostHealth(
        hostId: bastion.id,
        alias: bastion.alias,
        reachable: true,
        load1: 0,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 11, 3),
        k8s: const FleetK8sSummary(read: true, nodes: ['crc']),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpOpener(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
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
          coreOsAckStoreProvider.overrideWith((ref) async => acks),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => HostDashboardScreen(hostId: node.id),
                  ),
                ),
                child: const Text('open-node'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openNode(WidgetTester tester) async {
    await tester.tap(find.text('open-node'));
    // The dashboard runs timers; pump frames instead of settling.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('notice shows before any probe; Continue reads the node',
      (tester) async {
    await pumpOpener(tester);
    await openNode(tester);

    expect(find.byType(CoreOsNoticeSheetBody), findsOneWidget);
    expect(find.text(kCoreOsNoticeCopy), findsOneWidget);
    expect(pool.probes, isEmpty, reason: 'nothing after the facts read');

    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(CoreOsNoticeSheetBody), findsNothing);
    expect(await acks.isAcknowledged(node.id), isTrue);
    expect(pool.probes.map((p) => p.runtimeType), [DashboardProbe, CoreOsNodeProbe]);
    expect(find.text('CLUSTER NODE'), findsOneWidget);
    expect(find.text('update staged (417.94.202411201403-0), reboot pending'),
        findsOneWidget);
    expect(find.text('3 running'), findsOneWidget);
    // Linked to the bastion from cached node names only.
    expect(find.text('Node of cluster on «crc-bastion»'), findsOneWidget);
    expect(
      pool.hostsProbed.where((id) => id == bastion.id),
      isEmpty,
      reason: 'no SSH to the bastion',
    );
    await dispose(tester);
  });

  testWidgets('M48.1: scos host shows the OKD node notice', (tester) async {
    await repo.saveFacts(node.id, _rhcos.copyWith(osId: 'scos'));
    await pumpOpener(tester);
    await openNode(tester);

    final sheet = find.byType(CoreOsNoticeSheetBody);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('OKD node')), findsOneWidget);
    expect(find.text(kOkdNodeNoticeCopy), findsOneWidget);
    expect(find.text(kCoreOsNoticeCopy), findsNothing);
    expect(find.text('OpenShift node'), findsNothing);

    await tester.tap(find.text('Continue'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(await acks.isAcknowledged(node.id), isTrue);
    expect(find.text('CLUSTER NODE'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('M48.1: rhcos host notice is unchanged', (tester) async {
    await pumpOpener(tester);
    await openNode(tester);
    expect(find.text('OpenShift node'), findsOneWidget);
    expect(find.text(kCoreOsNoticeCopy), findsOneWidget);
    expect(find.text('OKD node'), findsNothing);
    await dispose(tester);
  });

  test('M48.1: notice title and copy by osId', () {
    expect(coreOsNoticeTitle('rhcos'), 'OpenShift node');
    expect(coreOsNoticeCopy('rhcos'), kCoreOsNoticeCopy);
    for (final id in ['scos', 'fcos']) {
      expect(coreOsNoticeTitle(id), 'OKD node', reason: id);
      expect(coreOsNoticeCopy(id), kOkdNodeNoticeCopy, reason: id);
    }
    expect(
      kOkdNodeNoticeCopy,
      'This is an OKD node. SSH logins on nodes leave an "accessed" mark that '
      'the cluster shows on the node. Kelola only reads. For cluster health, '
      'add the bastion instead.',
    );
    // rhcos copy unchanged from M48.
    expect(
      kCoreOsNoticeCopy,
      'This is an OpenShift node. Red Hat records SSH logins on nodes as an '
      '"accessed" mark that support may ask about. Kelola only reads. For '
      'cluster health, add the bastion instead.',
    );
  });

  testWidgets('not shown again after Continue', (tester) async {
    await acks.acknowledge(node.id);
    await pumpOpener(tester);
    await openNode(tester);

    expect(find.byType(CoreOsNoticeSheetBody), findsNothing);
    expect(pool.probes.whereType<DashboardProbe>(), hasLength(1));
    expect(pool.probes.whereType<CoreOsNodeProbe>(), hasLength(1));
    await dispose(tester);
  });

  testWidgets('Cancel runs nothing and leaves the host', (tester) async {
    await pumpOpener(tester);
    await openNode(tester);

    expect(find.byType(CoreOsNoticeSheetBody), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(pool.probes, isEmpty);
    expect(await acks.isAcknowledged(node.id), isFalse);
    expect(find.byType(HostDashboardScreen), findsNothing);
    expect(find.text('open-node'), findsOneWidget);

    // Asked again next time.
    await openNode(tester);
    expect(find.byType(CoreOsNoticeSheetBody), findsOneWidget);
    await dispose(tester);
  });

  test('acknowledgement travels in the vault prefs record', () async {
    final store = VaultStore(
      db: db,
      hosts: repo,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
      coreOsAckOf: () async => acks,
    );
    await acks.acknowledge(node.id);
    await acks.acknowledge('deleted-host');
    final records = await store.localRecords();
    final prefs = records.firstWhere((r) => r.kind == VaultRecordKind.pref);
    expect(prefs.payload['coreOsAck'], [node.id]);

    final other = CoreOsAckStore.memory();
    final otherStore = VaultStore(
      db: db,
      hosts: repo,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
      coreOsAckOf: () async => other,
    );
    await otherStore.apply(
      VaultDiff(added: const [], updated: [prefs], deleted: const []),
    );
    expect(await other.isAcknowledged(node.id), isTrue);
  });

  test('Kubernetes home refreshes node names only on an existing fleet row',
      () async {
    await repo.saveClusterNodeNames(
      hostId: node.id,
      summary: const FleetK8sSummary(read: true, nodes: ['x']),
    );
    expect((await repo.loadFleetCacheByHost()).containsKey(node.id), isFalse);

    await repo.saveClusterNodeNames(
      hostId: bastion.id,
      summary: const FleetK8sSummary(read: true, nodes: ['crc', 'worker-9']),
    );
    final row = (await repo.loadFleetCacheByHost())[bastion.id]!;
    expect(row.k8s!.nodes, ['crc', 'worker-9']);
    expect(row.k8s!.read, isTrue);
  });

  test('vault host tombstone also drops the cluster-kind entry', () async {
    final kinds = ClusterKindStore.memory();
    await kinds.write(
      node.id,
      ClusterKindRecord(isOpenShift: true, readAt: DateTime.utc(2026, 11, 3)),
    );
    final store = VaultStore(
      db: db,
      hosts: repo,
      tunnels: TunnelRepository(db),
      selectionOf: () async => FleetProbeSelectionStore.memory(),
      clusterKindOf: () async => kinds,
    );
    await store.apply(
      VaultDiff(
        added: const [],
        updated: const [],
        deleted: [
          VaultRecord(
            id: node.id,
            kind: VaultRecordKind.host,
            updatedAt: DateTime.utc(2026, 11, 4),
            deviceId: 'other',
            payload: const {},
            tombstone: true,
          ),
        ],
      ),
    );
    expect(await repo.get(node.id), isNull);
    expect(await kinds.read(node.id), isNull);
  });

  test('ack store file round-trip and junk tolerance', () async {
    final dir = await Directory.systemTemp.createTemp('kelola_ack');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/coreos_node_ack.json');
    final store = CoreOsAckStore(file);
    expect(await store.isAcknowledged('h1'), isFalse);
    await store.acknowledge('h1');
    await store.merge(['h2']);
    expect(await CoreOsAckStore(file).read(), {'h1', 'h2'});
    await file.writeAsString('not json');
    expect(await CoreOsAckStore(file).read(), isEmpty);
  });
}

class _NodePool extends SshSessionPool {
  _NodePool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final probes = <Probe<dynamic>>[];
  final hostsProbed = <String>[];

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
    hostsProbed.add(host.id);
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
    if (probe is CoreOsNodeProbe) {
      return parseCoreOsNode(
        [
          '---HOSTNAME---',
          'crc',
          '---OSTREE---',
          _fixture('synthetic_rpm_ostree_status.json'),
          '---UNITS---',
          'active',
          'active',
          '---KUBELET---',
          '',
          '---CRICTL---',
          _fixture('synthetic_crictl_ps.json'),
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
