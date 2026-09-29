import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/presentation/widgets/confirm_package_action.dart';
import 'package:kelola/providers.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  testWidgets('apply updates uses DestructiveConfirmSheet, not AlertDialog',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
        ],
        child: KelolaApp(
          home: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  confirmPackageApply(
                    context,
                    hostAlias: 'nas-01',
                    names: const ['openssl', 'curl'],
                    securityOnly: false,
                    rebootRequired: false,
                  );
                },
                child: const Text('go'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(DestructiveConfirmSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Apply 2 updates?'), findsOneWidget);
    expect(find.textContaining('Never auto-applied'), findsOneWidget);
    expect(find.textContaining('openssl'), findsWidgets);
  });
}
