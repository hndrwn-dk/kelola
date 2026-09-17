import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

void main() {
  void phoneStatusBar(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
  }

  testWidgets('KelolaWashScaffold keeps AppBar title below status bar',
      (tester) async {
    phoneStatusBar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: AppBar(
            title: const Text('WashTitle'),
            backgroundColor: Colors.transparent,
            forceMaterialTransparency: true,
          ),
          body: const ColoredBox(color: Colors.black, child: Text('body')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('WashTitle')).dy, greaterThanOrEqualTo(48));
    // Body starts at or below chrome — no double status gap (> 48+80).
    final bodyTop = tester.getTopLeft(find.text('body')).dy;
    expect(bodyTop, lessThan(48 + 80 + 24),
        reason: 'status bar must not be padded twice above the body');
  });

  testWidgets('HostsRootBar wordmark and actions clear status bar',
      (tester) async {
    phoneStatusBar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: HostsRootBar(
            summary: '2 · 1 needs attention',
            actions: [
              KelolaChromeIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Settings',
                onPressed: () {},
              ),
              KelolaChromeIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Add host',
                onPressed: () {},
              ),
            ],
          ),
          body: ListView(
            children: const [
              Text('INSIGHTS AUDIT'),
              SizedBox(height: 400),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Kelola')).dy, greaterThanOrEqualTo(48));
    expect(
      tester.getTopLeft(find.byTooltip('Settings')).dy,
      greaterThanOrEqualTo(48),
    );
    // No large void between summary and first inventory label — and body must
    // start at status + chrome height (Scaffold must not pad top again).
    final summaryBottom =
        tester.getBottomLeft(find.text('2 · 1 needs attention')).dy;
    final insightsTop = tester.getTopLeft(find.text('INSIGHTS AUDIT')).dy;
    expect(insightsTop, lessThan(48 + HostsRootBar.contentHeight + 8),
        reason: 'body must not sit a second status inset below the chrome');
    expect(insightsTop - summaryBottom, lessThan(40),
        reason: 'gap summary→insights must not include a second status inset');
  });

  testWidgets('Settings AppBar title clears status bar', (tester) async {
    phoneStatusBar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            backgroundColor: Colors.transparent,
            forceMaterialTransparency: true,
          ),
          body: const Text('settings-body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Settings')).dy,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('Audit AppBar title clears status bar', (tester) async {
    phoneStatusBar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: KelolaWashScaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: const Text('Audit'),
            backgroundColor: Colors.transparent,
            forceMaterialTransparency: true,
          ),
          body: const Text('audit-body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Audit')).dy,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('KelolaPage title clears status bar', (tester) async {
    phoneStatusBar(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: const KelolaPage(
          title: 'Add host',
          body: Text('page-body'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Add host')).dy,
      greaterThanOrEqualTo(48),
    );
  });
}
