import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';

void main() {
  test('KelolaHostAppBar preferredSize grows with a subtitle, not a fixed 56', () {
    const withSubtitle = KelolaHostAppBar(
      hostAlias: 'east-rock-uat',
      title: 'Rocky Linux 9.8',
    );
    const bare = KelolaHostAppBar(
      hostAlias: '',
      title: 'Host',
    );
    expect(withSubtitle.preferredSize.height, greaterThan(bare.preferredSize.height));
    expect(withSubtitle.preferredSize.height, isNot(56));
    expect(
      File('lib/design/kelola_components.dart').readAsStringSync().contains(
            'Size get preferredSize => const Size.fromHeight(barHeight)',
          ),
      isFalse,
      reason: 'preferredSize must not be a fixed barHeight again',
    );
  });

  test('OS subtitle keeps the pretty name; session facts stay one short row', () {
    expect(
      dashboardOsTitle('Rocky Linux 9.8 (Blue Onyx)'),
      'Rocky Linux 9.8 (Blue Onyx)',
    );
    expect(dashboardOsTitle(null), isNull);
    expect(dashboardOsTitle('unknown'), isNull);

    final facts = dashboardSessionFacts(
      disconnected: false,
      uptime: '7h',
      pollMs: 5566,
    );
    expect(facts, ['up 7h', 'poll 5.6s']);
    expect(facts.join(' '), isNot(contains('StrongBox')));
    expect(facts.join(' '), isNot(contains('ms')));
    expect(facts, hasLength(lessThan(4)));

    expect(
      dashboardSessionFacts(disconnected: true, uptime: '7h', pollMs: 100),
      ['Disconnected'],
    );
    expect(dashboardPollLabel(850), 'poll 850ms');
    expect(dashboardPollLabel(1316), 'poll 1.3s');
  });

  testWidgets('dashboard app bar shows the OS, not the word Host', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          appBar: const KelolaHostAppBar(
            hostAlias: 'east-rock-uat',
            title: 'Rocky Linux 9.8 (Blue Onyx)',
          ),
          body: const Text('LOAD 1M'),
        ),
      ),
    );
    expect(find.text('east-rock-uat'), findsOneWidget);
    expect(find.textContaining('Rocky Linux 9.8'), findsOneWidget);
    expect(find.text('Host'), findsNothing);

    final bar = tester.renderObject<RenderBox>(find.byType(AppBar));
    final body = tester.renderObject<RenderBox>(find.text('LOAD 1M'));
    final barBottom = bar.localToGlobal(Offset.zero).dy + bar.size.height;
    final bodyTop = body.localToGlobal(Offset.zero).dy;
    expect(bodyTop, greaterThanOrEqualTo(barBottom - 0.5));
  });

  testWidgets('session fact chips stay on one row at a phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: DashboardSessionFacts(
            facts: dashboardSessionFacts(
              disconnected: false,
              uptime: '7h',
              pollMs: 1316,
            ),
            readOnly: true,
          ),
        ),
      ),
    );
    expect(find.text('up 7h'), findsOneWidget);
    expect(find.text('poll 1.3s'), findsOneWidget);
    expect(find.text('READ-ONLY'), findsOneWidget);
    final row = tester.getRect(find.byType(DashboardSessionFacts));
    expect(row.height, lessThan(40));
  });
}
