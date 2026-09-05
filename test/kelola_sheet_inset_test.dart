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
          viewPadding: EdgeInsets.only(top: 44, bottom: 48),
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
    expect(inset.bottom, greaterThanOrEqualTo(300));
    // Keyboard open → protect status bar.
    expect(inset.top, 44);
  });

  testWidgets('kelolaSheetInset without keyboard uses nav padding only',
      (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(top: 44, bottom: 48),
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
    expect(inset.top, 0);
  });

  testWidgets('kelolaSheetInset pads top when child is near full viewport',
      (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
          viewPadding: EdgeInsets.only(top: 44, bottom: 48),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            inset = kelolaSheetInset(context, childHeight: 720);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(inset.top, 44);
  });

  testWidgets('kelolaSheetInset skips top for short sheets', (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          viewPadding: EdgeInsets.only(top: 44, bottom: 48),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            inset = kelolaSheetInset(context, childHeight: 220);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(inset.top, 0);
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

  testWidgets('kelolaSheetBodyHeight shrinks when keyboard is open',
      (tester) async {
    late double bodyH;
    late double maxH;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 48),
          viewInsets: EdgeInsets.only(bottom: 300),
          viewPadding: EdgeInsets.only(top: 44, bottom: 48),
          size: Size(400, 800),
        ),
        child: Builder(
          builder: (context) {
            bodyH = kelolaSheetBodyHeight(context);
            maxH = kelolaSheetMaxBodyHeight(context);
            return const SizedBox();
          },
        ),
      ),
    );
    // 800 - 44 top - 300 keyboard - 48 nav = 408 usable; body is 82% of that.
    expect(maxH, 408);
    expect(bodyH, closeTo(408 * 0.82, 0.01));
    expect(bodyH, lessThan(800 * 0.82));
  });
}
