import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/screens/settings_screen.dart';
import 'package:kelola/providers.dart';

Host _host(String alias, {HostAttention attention = HostAttention.healthy}) {
  return Host(
    id: alias,
    alias: alias,
    address: '10.0.0.8',
    port: 22,
    username: 'ops',
    keyAlias: 'kelola',
    attention: attention,
    attentionAt: DateTime.utc(2026, 9, 14, 8),
  );
}

class _FakeEntitlement implements Entitlement {
  _FakeEntitlement({required this.unlocked, required this.label});

  final bool unlocked;
  final String label;

  @override
  String get sourceLabel => label;

  @override
  bool isUnlocked(ProFeature feature) => unlocked;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  void initialize() {}

  @override
  Future<ProPurchaseResult> purchase() async => ProPurchaseResult.unavailable;

  @override
  Future<ProPurchaseResult> restore() async => ProPurchaseResult.unavailable;

  @override
  void dispose() {}
}

void main() {
  test('unreachable hosts are never grouped as healthy', () {
    final now = DateTime.utc(2026, 9, 14, 8, 2);
    final view = HostInventoryView.build(
      [
        _host('east-rock-uat', attention: HostAttention.unreachable),
        _host('east-worker-uat', attention: HostAttention.unreachable),
      ],
      now: now,
    );
    expect(view.healthy, isEmpty);
    expect(view.needsAttention.map((h) => h.alias), [
      'east-rock-uat',
      'east-worker-uat',
    ]);
    expect(view.summary, '2 · 2 needs attention');
    expect(view.summary, isNot(contains('healthy')));
  });

  test('unmonitored hosts leave healthy and needs attention', () {
    final view = HostInventoryView(
      needsAttention: [_host('down', attention: HostAttention.unreachable)],
      healthy: [_host('ok')],
      notChecked: const [],
    );
    final split = splitUnmonitored(view, (id) => id == 'kept');
    expect(split.monitored.healthy, isEmpty);
    expect(split.monitored.needsAttention, isEmpty);
    expect(split.unmonitored.map((h) => h.alias), ['down', 'ok']);
    expect(split.summary, isNot(contains('healthy')));
    expect(split.summary, contains('2 not monitored'));
  });

  testWidgets('Settings status follows unlock, not the build token', (
    tester,
  ) async {
    Future<void> pump(Entitlement entitlement) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            entitlementProvider.overrideWithValue(entitlement),
          ],
          child: KelolaApp(home: const SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(_FakeEntitlement(unlocked: false, label: 'ext'));
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Paid'), findsNothing);
    expect(find.text('Language'), findsNothing);
    expect(find.text('Theme'), findsNothing);
    expect(find.byType(HostsChromeAccent), findsOneWidget);
    expect(find.byType(HostGroupTray), findsOneWidget);
    expect(find.text('Source'), findsNothing);
    expect(find.text('License'), findsNothing);
    expect(find.text('About'), findsNothing);

    await pump(_FakeEntitlement(unlocked: true, label: 'std'));
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Free'), findsNothing);

    await tester.tap(find.text('Restore purchase'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing to restore on this build.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.text('$kelolaAppVersion · build $kelolaVersionCode · std'),
      findsOneWidget,
    );
    expect(find.text('Keys stay on this device'), findsOneWidget);
  });

  testWidgets('Hosts opens Settings; build token lives on Version row', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(HostRepository(db)),
          entitlementProvider.overrideWithValue(
            _FakeEntitlement(unlocked: true, label: 'std'),
          ),
        ],
        child: const KelolaApp(home: HostsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('v$kelolaAppVersion · std'), findsNothing);
    expect(find.byKey(HostsColophon.hairlineKey), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsOneWidget);
    expect(
      find.text('$kelolaAppVersion · build $kelolaVersionCode · std'),
      findsOneWidget,
    );
    expect(find.text('Keys stay on this device'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
