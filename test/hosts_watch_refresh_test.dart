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
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/providers.dart';

const _facts = HostFacts(
  osId: 'debian',
  osVersionId: '12',
  prettyName: 'Debian 12',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.apt,
  fw: FirewallBackend.nftables,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

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

class _ProbePool extends SshSessionPool {
  _ProbePool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  int executeCalls = 0;
  DashboardSnapshot snapshot = const DashboardSnapshot(
    uptime: Duration(hours: 1),
    load1: 0.1,
    cpuPercent: 1,
    memUsedPercent: 20,
    diskRootPercent: 40,
    failedUnitCount: 2,
    failedUnitNames: ['nginx.service'],
  );

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
    executeCalls++;
    if (probe is DashboardProbe) {
      return snapshot as T;
    }
    throw StateError('unexpected probe ${probe.runtimeType}');
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
  late _ProbePool pool;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
    pool = _ProbePool(repository: repo);
  });

  tearDown(() => db.close());

  Future<void> pumpHosts(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
          homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
          hardwareSignerProvider.overrideWithValue(_BoomSigner()),
        ],
        child: const KelolaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settleDispose(WidgetTester tester) async {
    await db.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('insert while Hosts is mounted appears without restart',
      (tester) async {
    await pumpHosts(tester);
    expect(find.byType(HostsScreen), findsOneWidget);
    expect(find.text('Add host'), findsWidgets);

    await repo.insert(
      alias: 'edge-new',
      address: '10.0.0.3',
      port: 22,
      username: 'hendra',
    );
    await tester.pumpAndSettle();

    expect(find.text('edge-new'), findsOneWidget);
    await settleDispose(tester);
  });

  testWidgets('Fleet membership picks up insert while mounted', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
          homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
          hardwareSignerProvider.overrideWithValue(_BoomSigner()),
        ],
        child: const KelolaApp(
          home: FleetScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await repo.insert(
      alias: 'fleet-new',
      address: '10.0.0.4',
      port: 22,
      username: 'hendra',
    );
    await tester.pumpAndSettle();

    expect(find.text('fleet-new'), findsOneWidget);
    await settleDispose(tester);
  });

  testWidgets('insert while Hosts is covered still shows after pop',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          sessionPoolProvider.overrideWithValue(pool),
          homeWidgetBridgeProvider.overrideWithValue(const _NoopWidgetBridge()),
          hardwareSignerProvider.overrideWithValue(_BoomSigner()),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HostsScreen(),
                    ),
                  );
                },
                child: const Text('open-hosts'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-hosts'));
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(child: Text('covering')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('covering'), findsOneWidget);

    await repo.insert(
      alias: 'under-cover',
      address: '10.0.0.8',
      port: 22,
      username: 'hendra',
    );
    await tester.pumpAndSettle();

    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('under-cover'), findsOneWidget);
    await settleDispose(tester);
  });

  testWidgets(
      'attention change while Hosts visible moves the host to the matching group',
      (tester) async {
    final now = DateTime.now().toUtc();
    final healthy = await repo.insert(
      alias: 'stay-put',
      address: '10.0.0.5',
      port: 22,
      username: 'hendra',
    );
    await repo.updateAttention(
      id: healthy.id,
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 20,
      attentionAt: now.subtract(const Duration(minutes: 1)),
    );
    await repo.saveFacts(healthy.id, _facts);
    final other = await repo.insert(
      alias: 'anchor',
      address: '10.0.0.6',
      port: 22,
      username: 'hendra',
    );
    await repo.updateAttention(
      id: other.id,
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 20,
      attentionAt: now.subtract(const Duration(minutes: 1)),
    );
    await repo.saveFacts(other.id, _facts);

    await pumpHosts(tester);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('NEEDS ATTENTION'), findsNothing);

    final list = find.byType(Scrollable);
    await tester.drag(list.first, const Offset(0, -40));
    await tester.pump();

    await repo.updateAttention(
      id: healthy.id,
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 20,
      attentionAt: DateTime.now().toUtc(),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('stay-put'), findsOneWidget);
    expect(find.text('2 FAILED'), findsOneWidget);
    expect(find.text('anchor'), findsOneWidget);
    await settleDispose(tester);
  });

  testWidgets('pull-to-refresh probes then reorders', (tester) async {
    final now = DateTime.now().toUtc();
    final host = await repo.insert(
      alias: 'probe-me',
      address: '10.0.0.7',
      port: 22,
      username: 'hendra',
    );
    await repo.updateAttention(
      id: host.id,
      attention: HostAttention.healthy,
      failedUnitCount: 0,
      diskRootPercent: 20,
      attentionAt: now.subtract(const Duration(minutes: 1)),
    );
    await repo.saveFacts(host.id, _facts);

    await pumpHosts(tester);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(pool.executeCalls, 0);

    await tester.fling(
      find.byType(RefreshIndicator),
      const Offset(0, 300),
      1000,
    );
    await tester.pumpAndSettle();

    expect(pool.executeCalls, greaterThan(0));
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.text('probe-me'), findsOneWidget);
    final stored = await repo.get(host.id);
    expect(stored!.attention, HostAttention.failedUnits);
    await settleDispose(tester);
  });
}
