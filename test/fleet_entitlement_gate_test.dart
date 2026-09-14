import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/fleet/fleet_probe_selection_store.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/pro_locked_sheet.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

class _ScriptedEntitlement implements Entitlement {
  _ScriptedEntitlement({required this.unlocked});

  bool unlocked;
  final _changes = StreamController<void>.broadcast();

  void setUnlocked(bool value) {
    unlocked = value;
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  void dispose() => _changes.close();

  @override
  void initialize() {}

  @override
  bool isUnlocked(ProFeature feature) => unlocked;

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  String get sourceLabel => 'std';
}

class _ExistsSigner implements HardwareSigner {
  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {}

  @override
  Future<void> deleteKey(String alias) async {}

  @override
  Future<HardwareKey> generateKey(String alias) {
    throw StateError('no generate');
  }

  @override
  Future<bool> keyExists(String alias) async => true;

  @override
  Future<Uint8List> sign(String alias, Uint8List data) {
    throw StateError('no sign');
  }
}

class _RecordingPool extends SshSessionPool {
  _RecordingPool({required super.repository})
      : super(
          signer: _ExistsSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final probed = <String>[];

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
    probed.add(host.id);
    throw StateError('no ssh in test');
  }
}

class _NoopWidgetBridge implements HomeWidgetBridge {
  const _NoopWidgetBridge();

  @override
  Future<void> write(HomeWidgetSnapshot snap) async {}
}

void main() {
  late KelolaDatabase db;
  late HostRepository repo;
  late _RecordingPool pool;
  late FleetProbeSelectionStore selection;
  late _ScriptedEntitlement entitlement;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    pool = _RecordingPool(repository: repo);
    selection = FleetProbeSelectionStore.memory();
    entitlement = _ScriptedEntitlement(unlocked: false);
    await repo.saveDeviceKey(blobB64: 'YQ==', backend: 'test');
  });

  tearDown(() async {
    entitlement.dispose();
    await db.close();
  });

  List<Override> overrides() {
    return [
      databaseProvider.overrideWithValue(db),
      hostRepositoryProvider.overrideWithValue(repo),
      sessionPoolProvider.overrideWithValue(pool),
      hardwareSignerProvider.overrideWithValue(_ExistsSigner()),
      homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
      entitlementProvider.overrideWithValue(entitlement),
      fleetProbeSelectionStoreProvider.overrideWith((ref) async => selection),
    ];
  }

  Future<Host> addHost(String alias) {
    return repo.insert(
      alias: alias,
      address: '10.0.0.$alias',
      port: 22,
      username: 'ops',
    );
  }

  Future<void> seedCache(Host host, {double load1 = 7.25}) {
    return repo.saveFleetCache(
      FleetHostHealth(
        hostId: host.id,
        alias: host.alias,
        reachable: true,
        load1: load1,
        diskRootPercent: 12,
        failedUnitCount: 0,
        pendingUpdates: 0,
        fetchedAt: DateTime.utc(2026, 9, 1),
        outcome: HostProbeOutcome.healthy,
        fromCache: true,
      ),
    );
  }

  Future<void> markHealthy(Host host) {
    return repo.updateAttention(
      id: host.id,
      attention: HostAttention.healthy,
      attentionAt: DateTime.utc(2026, 9, 1),
      lastSeenAt: DateTime.utc(2026, 9, 1),
      failedUnitCount: 0,
      diskRootPercent: 12,
    );
  }

  Future<void> pumpScreen(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: KelolaApp(home: home),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('locked fleet still lists every host and probes only the selection',
      (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];
    for (final host in hosts) {
      await markHealthy(host);
      await seedCache(host);
    }
    await selection.write({hosts[0].id, hosts[2].id});

    await pumpScreen(tester, const FleetScreen());
    await tester.pump(const Duration(milliseconds: 200));

    for (final host in hosts) {
      expect(find.text(host.alias), findsWidgets);
    }
    expect(pool.probed.toSet(), {hosts[0].id, hosts[2].id});

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('locked fleet with no prior choice probes nobody and prompts',
      (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];

    await pumpScreen(tester, const FleetScreen());
    await tester.pump(const Duration(milliseconds: 200));

    for (final host in hosts) {
      expect(find.text(host.alias), findsWidgets);
    }
    expect(find.text('Choose up to 3 hosts to monitor.'), findsOneWidget);
    expect(pool.probed, isEmpty);
    expect(await selection.read(hosts.map((host) => host.id).toSet()), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('skipped host stays listed and the row still opens', (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];
    await selection.write({hosts[0].id});

    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpScreen(tester, const HostsScreen());
    await tester.pump(const Duration(milliseconds: 100));

    for (final host in hosts) {
      expect(find.text(host.alias), findsOneWidget);
    }
    expect(find.text('NOT MONITORED'), findsWidgets);

    final row = find.text('e');
    await tester.ensureVisible(row);
    await tester.pump();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(HostDashboardScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('hosts refresh still touches every host when fleet is locked',
      (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];
    await selection.write({hosts[0].id});

    await pumpScreen(tester, const HostsScreen());
    await tester.pump(const Duration(milliseconds: 100));
    pool.probed.clear();

    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator).last,
    );
    await indicator.onRefresh();
    await tester.pump();

    expect(pool.probed.toSet(), hosts.map((h) => h.id).toSet());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('skipped host does not write attention and cache returns on unlock',
      (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];
    final skipped = hosts[4];
    for (final host in hosts) {
      await markHealthy(host);
      await seedCache(host, load1: host.id == skipped.id ? 7.25 : 0.2);
    }
    await selection.write({hosts[0].id});

    await pumpScreen(tester, const FleetScreen());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('not monitored'), findsWidgets);
    expect(find.text('7.25'), findsNothing);

    final afterSkip = (await repo.watchList().first)
        .firstWhere((h) => h.id == skipped.id);
    expect(afterSkip.attention, HostAttention.healthy);
    expect(
      afterSkip.attentionAt?.toUtc(),
      DateTime.utc(2026, 9, 1),
    );
    final cache = await repo.loadFleetCacheByHost();
    expect(cache[skipped.id]?.load1, 7.25);

    entitlement.setUnlocked(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('7.25'), findsOneWidget);
    expect(find.text('not monitored'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('fourth probe and fourth host open ProLockedCard without saving',
      (tester) async {
    final hosts = [
      for (final alias in ['a', 'b', 'c', 'd', 'e']) await addHost(alias),
    ];
    await selection.write({hosts[0].id, hosts[1].id, hosts[2].id});

    await pumpScreen(tester, const HostsScreen());
    await tester.pump(const Duration(milliseconds: 100));

    final toggle = find.byKey(Key('probe-toggle-${hosts[3].id}'));
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.byType(ProLockedCard), findsOneWidget);

    final stored = await selection.read(hosts.map((h) => h.id).toSet());
    expect(stored, isNotNull);
    expect(stored!.contains(hosts[3].id), isFalse);

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add host'));
    await tester.pumpAndSettle();
    expect(find.byType(ProLockedCard), findsOneWidget);
    expect(await repo.watchList().first, hasLength(5));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('unavailable purchase leaves the sheet open without a snackbar',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: KelolaApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () => showProLockedSheet(
                    context,
                    title: 'Tunnels',
                    body: 'A local SSH port forward stays locked in this build.',
                    onPurchase: () async => ProPurchaseResult.unavailable,
                  ),
                  child: const Text('locked'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('locked'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(find.byType(KelolaSheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('http'), findsNothing);
  });

  testWidgets('colophon build token sits on the version line', (tester) async {
    await pumpScreen(tester, const HostsScreen());
    await tester.pump(const Duration(milliseconds: 100));

    final label = find.text('v$kelolaAppVersion · std');
    expect(label, findsOneWidget);
    expect(find.text('open-source'), findsNothing);
    expect(find.text('std'), findsNothing);
    final row = find.ancestor(of: label, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.text('Keys stay on this device')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
