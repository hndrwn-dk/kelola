import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/widgets/diagnostic_pack_sheet.dart';

void main() {
  testWidgets('preview shows the exact pack and cancel does not share',
      (tester) async {
    const pack = '## kelola\nkelola: 0.1.0\nflutter: 3.47\n';
    var shared = 0;
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showDiagnosticPackPreview(
                  context,
                  pack: pack,
                  share: (text) async {
                    shared++;
                    expect(text, pack);
                  },
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(pack), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(shared, 0);
  });

  testWidgets('share sends the previewed pack through the callback',
      (tester) async {
    const pack = 'attention: failedUnits\n';
    var shared = '';
    await tester.pumpWidget(
      KelolaApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showDiagnosticPackPreview(
                  context,
                  pack: pack,
                  share: (text) async {
                    shared = text;
                  },
                );
              },
              child: const Text('go'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, pack);
  });
}
