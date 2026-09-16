import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';

Host _host({
  required String alias,
  HostAttention attention = HostAttention.healthy,
  DateTime? attentionAt,
}) {
  return Host(
    id: alias,
    alias: alias,
    address: '10.0.0.1',
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    attention: attention,
    attentionAt: attentionAt ?? DateTime.utc(2026, 9, 16),
  );
}

FleetHostHealth _cache({
  required String hostId,
  bool reachable = true,
  double load1 = 0.4,
  int nproc = 4,
  int mem = 45,
  int? disk = 83,
}) {
  return FleetHostHealth(
    hostId: hostId,
    alias: hostId,
    reachable: reachable,
    load1: load1,
    diskRootPercent: disk,
    failedUnitCount: 0,
    pendingUpdates: 0,
    fetchedAt: DateTime.utc(2026, 9, 16),
    nprocCores: nproc,
    memPercent: mem,
  );
}

void main() {
  test('summary is compact: count and attention, no healthy echo', () {
    final now = DateTime.utc(2026, 9, 16);
    final view = HostInventoryView.build([
      _host(
        alias: 'a',
        attention: HostAttention.failedUnits,
        attentionAt: now,
      ),
      _host(
        alias: 'b',
        attention: HostAttention.healthy,
        attentionAt: now,
      ),
    ], now: now);
    expect(view.summary, '2 · 1 needs attention');
    expect(view.summary, isNot(contains('healthy')));
    expect(view.summary, isNot(contains('hosts')));
  });

  test('inventory metrics: L-prefix load; omit unknown disk; never invent zeros',
      () {
    final ok = _host(alias: 'nas');
    final down = _host(alias: 'edge', attention: HostAttention.unreachable);
    expect(
      hostInventoryMetricsLine(
        host: ok,
        monitored: true,
        cache: _cache(hostId: 'nas'),
      ),
      'L10% · 45% · 83%',
    );
    expect(
      hostInventoryMetricsLine(
        host: ok,
        monitored: true,
        cache: _cache(hostId: 'nas', disk: null),
      ),
      'L10% · 45%',
    );
    expect(
      hostInventoryMetricsLine(host: ok, monitored: true, cache: null),
      isNull,
    );
    expect(
      hostInventoryMetricsLine(
        host: ok,
        monitored: false,
        cache: _cache(hostId: 'nas'),
      ),
      isNull,
    );
    expect(
      hostInventoryMetricsLine(
        host: down,
        monitored: true,
        cache: _cache(hostId: 'edge'),
      ),
      isNull,
    );
    expect(
      hostInventoryMetricsLine(
        host: ok,
        monitored: true,
        cache: _cache(hostId: 'nas', reachable: false),
      ),
      isNull,
    );
  });

  test('hosts chrome accent painter source is unchanged by this feature', () {
    final chrome = File('lib/design/kelola_components.dart').readAsStringSync();
    final start = chrome.indexOf('class HostsChromeAccent');
    expect(start, greaterThan(-1));
    final block = chrome.substring(start, start + 1200);
    expect(block, contains('CustomPaint'));
    expect(block, contains('amber'));
  });

  test('hosts screen flows rail after inventory; hide rail when empty; colophon pinned',
      () {
    final src = File('lib/presentation/screens/hosts_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(src, contains('HostsChromeAccent'));
    expect(src, contains('HostsUtilityRail'));
    expect(src, contains('HostsColophon'));
    expect(src, contains('loadFleetCacheByHost'));
    expect(src, contains('_utilityTrail'));
    expect(src, contains('..._utilityTrail(plan)'));
    expect(src, contains('hostInventoryMetricsLine'));
    expect(src, contains('SafeArea(\n                top: false'));
    final trail = src.substring(
      src.indexOf('List<Widget> _utilityTrail'),
      src.indexOf('bool _groupExpanded'),
    );
    expect(trail, contains('HostsUtilityRail'));
    expect(trail, isNot(contains('HostsColophon')));
    final footerStart = src.indexOf('SafeArea(\n                top: false');
    final footer = src.substring(footerStart, footerStart + 400);
    expect(footer, contains('HostsColophon'));
    expect(footer, isNot(contains('HostsUtilityRail')));
    // Empty state must not call the utility trail.
    final emptyBlock = src.substring(
      src.indexOf('if (list.isEmpty)'),
      src.indexOf('final view = inventory'),
    );
    expect(emptyBlock, isNot(contains('_utilityTrail')));
    expect(src, isNot(contains('FleetHealthProbe')));
  });

  testWidgets('utility rail shows icons and real state; widget color follows on/off',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: HostsUtilityRail(
            fleetMeta: '2 hosts',
            assistMeta: 'set up',
            widgetMeta: 'off',
            widgetOn: false,
            onFleet: () {},
            onAssist: () {},
            onWidget: () {},
          ),
        ),
      ),
    );
    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('AI Assist'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('2 hosts'), findsOneWidget);
    expect(find.text('set up'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
    expect(find.byType(HostsFleetIcon), findsOneWidget);
    expect(find.byType(HostsAssistIcon), findsOneWidget);
    expect(find.byType(HostsWidgetIcon), findsOneWidget);
    expect(find.text('none'), findsNothing);

    final offIcon = tester.widget<HostsWidgetIcon>(find.byType(HostsWidgetIcon));
    expect(offIcon.on, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: HostsUtilityRail(
            fleetMeta: '2 hosts',
            assistMeta: 'ollama · llama3.2',
            widgetMeta: 'on',
            widgetOn: true,
            onFleet: () {},
            onAssist: () {},
            onWidget: () {},
          ),
        ),
      ),
    );
    final onIcon = tester.widget<HostsWidgetIcon>(find.byType(HostsWidgetIcon));
    expect(onIcon.on, isTrue);
    expect(find.text('ollama · llama3.2'), findsOneWidget);
  });

  test('no flutter_svg dependency for hosts icons', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('flutter_svg')));
  });
}
