import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';

void main() {
  testWidgets('back plate size matches overflow plate size', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          appBar: AppBar(
            leadingWidth: KelolaChromeIconButton.leadingWidth,
            leading: const Align(
              alignment: Alignment.center,
              child: KelolaBackButton(),
            ),
            actions: [
              KelolaChromeIconButton(
                icon: Icons.more_vert,
                tooltip: 'More',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final back = tester.getSize(find.byType(KelolaBackButton));
    final more = tester.getSize(
      find.byWidgetPredicate(
        (w) =>
            w is KelolaChromeIconButton && w.icon == Icons.more_vert,
      ),
    );
    expect(back, equals(more));
    expect(back.width, KelolaChromeIconButton.plateSize);
    expect(back.height, KelolaChromeIconButton.plateSize);
    // Must stay smaller than the default AppBar leading slot (56).
    expect(back.width, lessThan(48));
  });
}
