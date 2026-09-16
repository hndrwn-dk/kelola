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

  test('app bar subtitle keeps OS with uptime; no poll row', () {
    expect(
      dashboardOsTitle('Rocky Linux 9.8 (Blue Onyx)'),
      'Rocky Linux 9.8 (Blue Onyx)',
    );
    expect(
      dashboardAppBarSubtitle(
        os: 'Rocky Linux 9.8 (Blue Onyx)',
        uptime: '7h',
      ),
      'Rocky Linux 9.8 · Uptime 7h',
    );
    expect(dashboardOsTitle(null), isNull);
    expect(dashboardOsTitle('unknown'), isNull);
  });

  testWidgets('dashboard app bar shows the OS, not the word Host', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          appBar: const KelolaHostAppBar(
            hostAlias: 'east-rock-uat',
            title: 'Rocky Linux 9.8 · Uptime 14d',
          ),
          body: const Text('CPU'),
        ),
      ),
    );
    expect(find.text('east-rock-uat'), findsOneWidget);
    expect(find.textContaining('Rocky Linux 9.8'), findsOneWidget);
    expect(find.textContaining('Uptime 14d'), findsOneWidget);
    expect(find.text('Host'), findsNothing);

    final bar = tester.renderObject<RenderBox>(find.byType(AppBar));
    final body = tester.renderObject<RenderBox>(find.text('CPU'));
    final barBottom = bar.localToGlobal(Offset.zero).dy + bar.size.height;
    final bodyTop = body.localToGlobal(Offset.zero).dy;
    expect(bodyTop, greaterThanOrEqualTo(barBottom - 0.5));
  });

  test('dashboard source has no session fact row between bar and cards', () {
    final src = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(src, isNot(contains('DashboardSessionFacts')));
    expect(src, isNot(contains('dashboardPollLabel')));
    expect(src, contains('dashboardAppBarSubtitle'));
  });
}
