import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';

void main() {
  testWidgets('kelolaSheetInset adds keyboard viewInsets and nav padding',
      (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
          viewInsets: EdgeInsets.only(bottom: 300),
          viewPadding: EdgeInsets.only(bottom: 48),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            inset = kelolaSheetInset(context);
            return const SizedBox();
          },
        ),
      ),
    );
    // padding.bottom stays available when we sum with viewInsets in helper;
    // with keyboard up Flutter often zeros padding — either way helper must
    // include viewInsets.
    expect(inset.bottom, greaterThanOrEqualTo(300));
  });

  testWidgets('kelolaSheetInset without keyboard uses nav padding only',
      (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(bottom: 48),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            inset = kelolaSheetInset(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(inset.bottom, 48);
  });

  testWidgets('kelolaScrollPadding uses viewPadding.bottom plus extra',
      (tester) async {
    late EdgeInsets pad;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(bottom: 40),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            pad = kelolaScrollPadding(
              context,
              left: 14,
              top: 0,
              right: 14,
              extraBottom: 16,
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(pad.left, 14);
    expect(pad.top, 0);
    expect(pad.right, 14);
    expect(pad.bottom, 56);
  });

  testWidgets('KelolaSheet applies sheet inset around child', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 24),
          viewPadding: EdgeInsets.only(bottom: 24),
          size: Size(400, 800),
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: KelolaSheet(
              child: SizedBox(key: Key('body'), height: 80),
            ),
          ),
        ),
      ),
    );
    final sheet = tester.widget<Padding>(
      find
          .descendant(
            of: find.byType(KelolaSheet),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(sheet.padding, const EdgeInsets.only(bottom: 24));
    expect(find.byKey(const Key('body')), findsOneWidget);
  });
}
