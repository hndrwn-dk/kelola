import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/host_env/host_env.dart';
import 'package:kelola/presentation/host_env/env_bindings_sheet.dart';
import 'package:kelola/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tag editor keeps Name, Value, and Save above the keyboard', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(HostRepository(db)),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showTagEnvironmentsSheet(context: context),
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
    await tester.tap(find.text('Add variable'));
    await tester.pumpAndSettle();

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.reset);
    await tester.pump();

    expect(find.text('Name').hitTestable(), findsOneWidget);
    expect(find.text('Value').hitTestable(), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(save.hitTestable(), findsOneWidget);
    final mq = MediaQuery.of(tester.element(save));
    final visibleBottom = mq.size.height - mq.viewInsets.bottom;
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(visibleBottom));

    await tester.enterText(find.byType(TextField).at(0), 'Prod');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester.widget<EditableText>(find.byType(EditableText).at(1)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('saving a Prod tag variable stores the name and value', (
    tester,
  ) async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  onPressed: () => showTagEnvironmentsSheet(context: context),
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
    await tester.tap(find.text('Add variable'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Prod');
    await tester.enterText(fields.at(1), 'REGION');
    await tester.enterText(fields.at(2), 'us-east');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final rows = await repo.listEnvBindings();
    expect(rows, hasLength(1));
    expect(rows.single.scope, EnvScope.tag);
    expect(rows.single.scopeId, 'prod');
    expect(rows.single.name, 'REGION');
    expect(rows.single.value, 'us-east');
  });
}
