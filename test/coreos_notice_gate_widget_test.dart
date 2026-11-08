import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/hosts/coreos_ack_store.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

import 'support/fakes.dart';

/// M48 §4 wiring: Hosts refresh and Fleet never SSH into an OpenShift/OKD
/// node whose first-connect notice is not acknowledged.
void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _Pool pool;
  late CoreOsAckStore acks;
  late Host web;
  late Host node;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    pool = _Pool(repository: repo);
    acks = CoreOsAckStore.memory();
    await repo.saveDeviceKey(blobB64: 'YQ==', backend: 'test');
    web = await repo.insert(
      alias: 'web',
      address: '10.0.0.10',
      port: 22,
      username: 'ops',
    );
    node = await repo.insert(
      alias: 'okd-node',
      address: '10.0.0.11',
      port: 22,
      username: 'core',
    );
    await repo.saveFacts(web.id, HostFacts.undiscovered.copyWith(osId: 'debian'));
    await repo.saveFacts(node.id, HostFacts.undiscovered.copyWith(osId: 'scos'));
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          sessionPoolProvider.overrideWithValue(pool),
          hardwareSignerProvider.overrideWithValue(_ExistsSigner()),
          homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
          entitlementProvider.overrideWithValue(FixedEntitlement(unlocked: true)),
          fleetProbeSelectionStoreProvider
              .overrideWith((ref) async => FleetProbeSelectionStore.memory()),
          coreOsAckStoreProvider.overrideWith((ref) async => acks),
        ],
        child: KelolaApp(home: home),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('Fleet skips the unacknowledged node and says why',
      (tester) async {
    await pump(tester, const FleetScreen());

    expect(pool.hostIds, [web.id]);
    final tile = tester.widget<FleetHostTile>(
      find.widgetWithText(FleetHostTile, 'okd-node'),
    );
    expect(tile.reachable, isFalse);
    expect(tile.downMessage, 'confirm on host first');
    await dispose(tester);
  });

  testWidgets('Fleet probes the node once it is acknowledged', (tester) async {
    await acks.acknowledge(node.id);
    await pump(tester, const FleetScreen());

    expect(pool.hostIds.toSet(), {web.id, node.id});
    final tile = tester.widget<FleetHostTile>(
      find.widgetWithText(FleetHostTile, 'okd-node'),
    );
    expect(tile.downMessage, isNot('confirm on host first'));
    await dispose(tester);
  });

  testWidgets('Hosts pull-to-refresh pings the host, not the node',
      (tester) async {
    await pump(tester, const HostsScreen());
    pool.hostIds.clear();
    pool.kinds.clear();

    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 600),
      1000,
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(pool.kinds, contains(DashboardProbe));
    expect(pool.hostIds, [web.id]);
    await dispose(tester);
  });
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: _ExistsSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final hostIds = <String>[];
  final kinds = <Type>[];

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
    hostIds.add(host.id);
    kinds.add(probe.runtimeType);
    if (probe is FleetHealthProbe) {
      return FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: 0.1,
        nprocCores: 2,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 11, 5),
      ) as T;
    }
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
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

class _ExistsSigner extends NoSshSigner {
  @override
  Future<bool> keyExists(String alias) async => true;
}

class _NoopWidgetBridge implements HomeWidgetBridge {
  const _NoopWidgetBridge();

  @override
  Future<void> write(HomeWidgetSnapshot snap) async {}
}
