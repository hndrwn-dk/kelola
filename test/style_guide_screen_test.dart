import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/design/style_guide_screen.dart';

void main() {
  testWidgets('style guide shows every design-system component', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _loadKelolaFonts();

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: RepaintBoundary(
          key: boundaryKey,
          child: const StyleGuideScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RiskBand), findsWidgets);
    expect(find.byType(StatCard), findsNWidgets(4));
    expect(find.byType(ServiceRow), findsNWidgets(8));
    expect(find.byType(SectionSlab), findsNWidgets(5));
    expect(find.byType(OsIcon), findsNWidgets(11));
    expect(find.byType(ToolTile), findsNWidgets(2));
    expect(find.byType(FilterPill), findsNWidgets(5));
    expect(find.byType(KelolaInput), findsNWidgets(2));
    expect(find.byType(MutateConfirmDialog), findsOneWidget);
    expect(find.byType(JournalLogLine), findsNWidgets(3));
    expect(find.byType(Sparkline), findsOneWidget);
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(KickerLine), findsNWidgets(2));
    expect(find.byType(ActionableError), findsOneWidget);
    expect(find.byType(DashboardStatusLine), findsNWidgets(4));
    expect(find.byType(KelolaBrandMark), findsOneWidget);
    expect(find.byType(HostHeroCard), findsOneWidget);
    expect(find.byType(FactGroup), findsOneWidget);
    expect(find.byType(AuditInsightRow), findsOneWidget);
    expect(find.byType(HostsChromeAccent), findsOneWidget);
    expect(find.byType(HostGroupTray), findsWidgets);
    expect(find.byType(CollapsedHostGroup), findsOneWidget);
    expect(find.byType(HostsColophon), findsOneWidget);
    expect(find.text('READ-ONLY'), findsOneWidget);

    expect(find.text('sshd.service'), findsOneWidget);
    expect(find.text('nginx.service'), findsOneWidget);
    expect(find.text('Stop sshd.service?'), findsOneWidget);
    expect(find.text('LOAD 1M'), findsOneWidget);
    expect(find.text('MEMORY'), findsOneWidget);

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test/goldens/style_guide.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });
}

Future<void> _loadKelolaFonts() async {
  Future<void> load(String family, String asset) async {
    final loader = FontLoader(family)..addFont(rootBundle.load(asset));
    await loader.load();
  }

  await load('SpaceGrotesk', 'assets/fonts/SpaceGrotesk.ttf');
  await load('IBMPlexSans', 'assets/fonts/IBMPlexSans.ttf');
  await load('IBMPlexMono', 'assets/fonts/IBMPlexMono-Regular.ttf');
}
