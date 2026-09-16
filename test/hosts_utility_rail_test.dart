import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  testWidgets('HostsUtilityRail shows three cells and keeps colophon hairline',
      (tester) async {
    var fleet = 0;
    var assist = 0;
    var widgetTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: Column(
            children: [
              HostsUtilityRail(
                fleetMeta: 'grid',
                assistMeta: 'set up',
                widgetMeta: 'off',
                onFleet: () => fleet++,
                onAssist: () => assist++,
                onWidget: () => widgetTaps++,
              ),
              const HostsColophon(version: '0.1.0'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(HostsUtilityRail), findsOneWidget);
    expect(find.text('Fleet'), findsOneWidget);
    expect(find.text('AI Assist'), findsOneWidget);
    expect(find.text('Widget'), findsOneWidget);
    expect(find.text('grid'), findsOneWidget);
    expect(find.text('set up'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
    expect(find.byType(ServiceRow), findsNothing);

    await tester.tap(find.text('Fleet'));
    await tester.tap(find.text('AI Assist'));
    await tester.tap(find.text('Widget'));
    expect(fleet, 1);
    expect(assist, 1);
    expect(widgetTaps, 1);

    expect(find.byKey(HostsColophon.hairlineKey), findsOneWidget);
    final railBottom = tester.getBottomLeft(find.byType(HostsUtilityRail)).dy;
    final hairlineTop =
        tester.getTopLeft(find.byKey(HostsColophon.hairlineKey)).dy;
    expect(hairlineTop, greaterThan(railBottom));
  });

  test('hosts screen flows utility rail; colophon stays pinned at foot', () {
    final src = File('lib/presentation/screens/hosts_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(src, contains('HostsUtilityRail'));
    expect(src, contains('HostsColophon'));
    expect(src, contains('..._utilityTrail(plan)'));
    expect(src, isNot(contains("name: 'Home widget'")));
    expect(src, isNot(contains("name: 'Fleet'")));
    expect(src, contains('SafeArea(\n                top: false'));
    final trail = src.substring(
      src.indexOf('List<Widget> _utilityTrail'),
      src.indexOf('bool _groupExpanded'),
    );
    expect(trail, isNot(contains('HostsColophon')));
  });
}
