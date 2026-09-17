import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  testWidgets('KelolaWashScaffold mounts appBar on Scaffold and body can scroll',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: AppBar(
            title: const Text('Wash'),
            backgroundColor: Colors.transparent,
            forceMaterialTransparency: true,
          ),
          body: ListView(
            children: [
              for (var i = 0; i < 40; i++)
                ListTile(title: Text('row $i')),
              ListTile(key: key, title: const Text('row LAST')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    // Chrome is laid out in the body stack — not Scaffold.appBar — so the
    // preferred height cannot expand and steal the scroll viewport.
    expect(scaffold.appBar, isNull);
    expect(scaffold.extendBodyBehindAppBar, isFalse);

    final bodyBox = tester.getRect(find.byType(ListView));
    final screen = tester.getSize(find.byType(Scaffold).first);
    // Body must keep the majority of the viewport (not starved by a Column AppBar).
    expect(bodyBox.height, greaterThan(screen.height * 0.55));

    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('row LAST'), findsOneWidget);
  });

  testWidgets('HostsRootBar as wash chrome leaves inventory height',
      (tester) async {
    final last = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: HostsRootBar(
            summary: '2 hosts',
            actions: [
              KelolaChromeIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: () {},
              ),
            ],
          ),
          body: ListView(
            children: [
              for (var i = 0; i < 30; i++) Text('host $i'),
              Text(key: last, 'host LAST'),
              HostsUtilityRail(
                fleetMeta: '2 hosts',
                assistMeta: 'set up',
                widgetMeta: 'off',
                onFleet: () {},
                onAssist: () {},
                onWidget: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final listH = tester.getSize(find.byType(ListView)).height;
    final screenH = tester.getSize(find.byType(Scaffold)).height;
    expect(listH, greaterThan(screenH * 0.55));
    await tester.scrollUntilVisible(
      find.byKey(last),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('set up'), findsOneWidget);
    expect(find.text('off'), findsOneWidget);
  });

  testWidgets('Audit-style sheet scrolls a long command body and exposes Close',
      (tester) async {
    final long = List.generate(80, (i) => 'line $i of probe script').join('\n');
    final endKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return Center(
                child: TextButton(
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (ctx) {
                        return KelolaSheet(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: Text('Connection lost')),
                                  KelolaChromeIconButton(
                                    icon: Icons.close,
                                    tooltip: 'Close',
                                    onPressed: () => Navigator.of(ctx).pop(),
                                  ),
                                ],
                              ),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 240),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(long, style: const TextStyle(fontSize: 11)),
                                      Text(key: endKey, 'SCRIPT_END'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(endKey),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SCRIPT_END'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Connection lost'), findsNothing);
  });
}
