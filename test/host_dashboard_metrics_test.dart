import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';

void main() {
  test('app bar subtitle uses Uptime, not up', () {
    expect(
      dashboardAppBarSubtitle(
        os: 'Rocky Linux 9.8 (Blue Onyx)',
        uptime: '14d',
      ),
      'Rocky Linux 9.8 · Uptime 14d',
    );
    expect(
      dashboardAppBarSubtitle(os: null, uptime: '2h'),
      'Uptime 2h',
    );
    expect(dashboardAppBarSubtitle(os: 'unknown', uptime: null), isNull);
  });

  test('card denominators: cores and GiB pairs; no u/s/io abbreviations', () {
    expect(formatDashboardCpuDenom(4), '4 cores');
    expect(formatDashboardCpuDenom(1), '1 core');
    expect(formatDashboardCpuDenom(null), isNull);

    expect(
      formatDashboardGiBPair(kibUsed: 4 * 1024 * 1024, kibTotal: 16 * 1024 * 1024),
      '4.0 / 16.0 GiB',
    );
    expect(
      formatDashboardGiBPair(kibUsed: 2200 * 1024, kibTotal: 33300 * 1024),
      '2.1 / 32.5 GiB',
    );

    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, isNot(contains("u \${")));
    expect(src, isNot(contains(' · s ')));
    expect(src, isNot(contains(' · io ')));
    expect(src, isNot(contains('formatDashboardCpuDetail')));
    expect(src, contains('formatDashboardCpuDenom'));
    expect(src, contains('formatDashboardGiBPair'));
    expect(src, contains('DashboardLoadCard'));
    expect(src, isNot(contains('formatDashboardLoadCaption')));
  });

  test('parser exposes root disk kib and nproc cores for card denominators', () {
    final raw =
        File('test/fixtures/host_facts/dashboard_nas01.txt').readAsStringSync();
    final snap = const DashboardParser().parse(raw);
    expect(snap.diskRootPercent, 83);
    expect(snap.diskRootUsedKib, 376228864);
    expect(snap.diskRootTotalKib, 482344960);
    expect(snap.nprocCores, 4);
    expect(
      formatDashboardGiBPair(
        kibUsed: snap.diskRootUsedKib,
        kibTotal: snap.diskRootTotalKib,
      ),
      contains(' / '),
    );
    expect(formatDashboardCpuDenom(snap.nprocCores), '4 cores');
  });

  test('memory meter fraction matches used percent', () {
    const mem = MemBreakdown(
      totalKb: 1000,
      availableKb: 700,
      freeKb: 50,
      cachedKb: 400,
      buffersKb: 100,
      swapTotalKb: 0,
      swapFreeKb: 0,
    );
    expect(mem.usedPercent, 30);
    expect(mem.meterFraction, closeTo(0.3, 0.001));
  });

  test('load intervals are labeled 1m 5m 15m without cores', () {
    expect(
      formatDashboardLoadIntervals(0.02, 0.15, 0.40),
      [
        ('1m', '0.02'),
        ('5m', '0.15'),
        ('15m', '0.40'),
      ],
    );
  });

  test('sudo needs password uses warning tone, not error red', () {
    final src = File('lib/design/kelola_components.dart').readAsStringSync();
    final start = src.indexOf('class DashboardStatusLine');
    final end = src.indexOf('class SectionSlab', start);
    final block = src.substring(start, end);
    expect(block, contains('sudoNeedsPassword'));
    expect(block, contains('c.amber'));
    expect(block, isNot(contains('style: error')));
  });

  test('back and overflow share KelolaChromeIconButton treatment', () {
    final chrome = File('lib/design/kelola_components.dart').readAsStringSync();
    expect(chrome, contains('class KelolaChromeIconButton'));
    expect(chrome, contains('KelolaBackButton'));
    final dash = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(dash, contains('Icons.more_vert'));
    expect(dash, isNot(contains('more_horiz')));
    expect(dash, contains('KelolaChromeIconButton'));
  });

  testWidgets('chrome back and overflow plates match; title clears leading',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: buildKelolaDarkTheme(),
        home: const SizedBox.shrink(),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: KelolaHostAppBar(
            hostAlias: 'east-rock-uat',
            title: 'Rocky Linux 9.8 · Uptime 2h',
            actions: [
              HostDashboardMenuButton(
                onNote: () {},
                onEdit: () {},
                onDetails: () {},
                onAudit: () {},
                onRemove: () {},
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(KelolaBackButton), findsOneWidget);
    expect(find.byType(HostDashboardMenuButton), findsOneWidget);

    final backPlate = find.descendant(
      of: find.byType(KelolaBackButton),
      matching: find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == KelolaChromeIconButton.plateSize &&
            w.height == KelolaChromeIconButton.plateSize,
      ),
    );
    final morePlate = find.descendant(
      of: find.byType(HostDashboardMenuButton),
      matching: find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == KelolaChromeIconButton.plateSize &&
            w.height == KelolaChromeIconButton.plateSize,
      ),
    );
    expect(tester.getSize(backPlate), tester.getSize(morePlate));
    expect(tester.getSize(backPlate).width, KelolaChromeIconButton.plateSize);

    final alias = find.byKey(KelolaHostIdentity.aliasKey);
    expect(alias, findsOneWidget);
    final backRight = tester.getBottomRight(backPlate).dx;
    final titleLeft = tester.getTopLeft(alias).dx;
    expect(titleLeft, greaterThan(backRight + 4));
    expect(find.text('east-rock-uat'), findsOneWidget);
  });

  testWidgets('three equal StatCards keep denominators; load is full-width card',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'CPU',
                        value: '8',
                        unit: '%',
                        detail: '4 cores',
                        meterFraction: 0.08,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: StatCard(
                        label: 'Memory',
                        value: '7',
                        unit: '%',
                        detail: '2.1 / 33.3 GiB',
                        meterFraction: 0.07,
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: StatCard(
                        label: 'Disk /',
                        value: '24',
                        unit: '%',
                        detail: '4.0 / 16.9 GiB',
                        meterFraction: 0.24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const DashboardLoadCard(load1: 0.01, load5: 0.01, load15: 0.02),
              ],
            ),
          ),
        ),
      ),
    );

    final cards = find.byType(StatCard);
    expect(cards, findsNWidgets(3));
    for (final detail in ['4 cores', '2.1 / 33.3 GiB', '4.0 / 16.9 GiB']) {
      expect(
        find.text(detail),
        findsOneWidget,
        reason: 'denominator must stay visible: $detail',
      );
    }
    expect(find.byType(DashboardLoadCard), findsOneWidget);
    expect(find.text('1m'), findsOneWidget);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.text('0.01'), findsNWidgets(2));
    expect(find.text('0.02'), findsOneWidget);
    expect(find.textContaining('load '), findsNothing);

    final loadSize = tester.getSize(find.byType(DashboardLoadCard));
    final rowWidth = tester.getSize(find.byType(Row).first).width;
    expect(loadSize.width, closeTo(rowWidth, 0.5));
  });

  test('dashboard CPU denom prefers snapshot nproc over missing facts', () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, contains('dash.nprocCores'));
    expect(src, contains('formatDashboardCpuDenom'));
  });
}
