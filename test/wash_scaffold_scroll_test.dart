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
    expect(scaffold.appBar, isNotNull);
    expect(scaffold.extendBodyBehindAppBar, isTrue);

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

  testWidgets('HostsRootBar as Scaffold.appBar leaves inventory height',
      (tester) async {
    final last = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          extendBodyBehindAppBar: true,
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: MediaQueryData.fromView(
                        tester.view,
                      ).padding.top +
                      HostsRootBar.contentHeight,
                ),
                child: ListView(
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

  testWidgets('Audit-style sheet scrolls a long command body', (tester) async {
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
                      builder: (ctx) {
                        return KelolaSheet(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(long, style: const TextStyle(fontSize: 11)),
                                Text(key: endKey, 'SCRIPT_END'),
                              ],
                            ),
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
    await tester.scrollUntilVisible(
      find.byKey(endKey),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('SCRIPT_END'), findsOneWidget);
  });
}
