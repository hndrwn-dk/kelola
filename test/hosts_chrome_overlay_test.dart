import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

const _hairlineKey = Key('hosts-colophon-hairline');

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildKelolaDarkTheme(),
    home: Scaffold(
      backgroundColor: KelolaColors.dark.ink,
      body: child,
    ),
  );
}

void main() {
  testWidgets('colophon hairline is 1px full width and findable by key',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(const HostsColophon(version: '0.1.0')),
    );

    final hairline = find.byKey(_hairlineKey);
    expect(hairline, findsOneWidget);
    final size = tester.getSize(hairline);
    expect(size.height, 1);
    expect(size.width, closeTo(390 - 32, 0.5));
  });

  testWidgets('colophon version and keys sit adjacent, not at opposite edges',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(const HostsColophon(version: '0.1.0')),
    );

    final version = find.text('v0.1.0');
    final keys = find.text('Keys stay on this device');
    expect(version, findsOneWidget);
    expect(keys, findsOneWidget);

    expect(
      tester.getTopLeft(version).dy,
      closeTo(tester.getTopLeft(keys).dy, 6),
    );
    final gap =
        tester.getTopLeft(keys).dx - tester.getBottomRight(version).dx;
    expect(gap, inInclusiveRange(4, 16));

    final row = find.ancestor(of: version, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.byType(Expanded)),
      findsNothing,
    );
    expect(tester.widget<Row>(row).mainAxisSize, MainAxisSize.min);
  });

  testWidgets('hosts root bar is not an opaque surface slab', (tester) async {
    await tester.pumpWidget(
      _wrap(
        HostsRootBar(
          summary: '3 hosts',
          actions: const [],
        ),
      ),
    );

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(HostsRootBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.type, MaterialType.transparency);
    expect(
      material.color == null || material.color!.a < 1,
      isTrue,
    );
  });

  testWidgets('host group tray fill is translucent so ink and arcs show through',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const HostGroupTray(
          label: 'Healthy',
          child: SizedBox(height: 24),
        ),
      ),
    );

    final containers = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(HostGroupTray),
        matching: find.byType(Container),
      ),
    );
    final tray = containers.firstWhere((w) {
      final deco = w.decoration;
      return deco is BoxDecoration && deco.border != null;
    });
    final color = (tray.decoration! as BoxDecoration).color!;
    expect(color.a, lessThan(1));
    expect(color.a, greaterThan(0));
  });
}
