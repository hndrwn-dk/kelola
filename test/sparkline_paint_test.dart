import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  testWidgets('Sparkline CustomPaint fills the given width', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Sparkline(
              values: const [0.2, 0.8, 0.4],
              color: KelolaColors.dark.amber,
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(
      find.descendant(
        of: find.byType(Sparkline),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(size.width, 300);
    expect(size.height, 34);
  });
}
