import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/undo.dart';
import 'package:kelola/presentation/widgets/undo_snackbar.dart';

void main() {
  testWidgets('undo snackbar lasts 8s and Undo fires the callback',
      (tester) async {
    var undone = false;
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showUndoSnackBar(
                    context,
                    message: 'Disabled nginx.service',
                    onUndo: () => undone = true,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, const Duration(seconds: 8));
    expect(find.text('Disabled nginx.service'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);

    await tester.tap(find.byType(SnackBarAction));
    await tester.pump();
    expect(undone, isTrue);
  });

  testWidgets('letting the snackbar expire does not run undo', (tester) async {
    var undone = false;
    await tester.pumpWidget(
      KelolaApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showUndoSnackBar(
                    context,
                    message: 'Stopped nginx.service',
                    onUndo: () => undone = true,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.byType(SnackBarAction), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(seconds: 1));
    expect(undone, isFalse);
  });

  test('unit detail offers undo only after a reversible mutate via execute', () {
    final src =
        File('lib/presentation/screens/unit_detail_screen.dart').readAsStringSync();
    expect(src, contains('undoProbeFor'));
    expect(src, contains('showUndoSnackBar'));
    expect(src, contains('runHostProbe'));
  });

  test('destructive disable never promises undo', () {
    expect(
      undoProbeFor(
        const UnitActionProbe(
          unitName: 'sshd.service',
          verb: UnitVerb.disable,
        ),
      ),
      isNull,
    );
  });
}
