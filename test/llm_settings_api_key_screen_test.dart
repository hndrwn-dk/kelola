import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/secrets/secret_store.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/presentation/screens/llm_settings_screen.dart';
import 'package:kelola/providers.dart';

void main() {
  testWidgets('reopening settings never puts the stored key in the tree',
      (tester) async {
    const fullKey = 'sk-abcdefghij3W5x';
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final secrets = MemorySecretStore();
    final repo = HostRepository(db, secrets: secrets);
    await repo.saveLlmSettingsBundle(
      const LlmSettingsBundle().persistEdit(
        draftProvider: LlmProvider.openaiCompatible,
        draftConfig: LlmEndpointConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          apiKey: fullKey,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          hostRepositoryProvider.overrideWithValue(repo),
          secretStoreProvider.overrideWithValue(secrets),
        ],
        child: const KelolaApp(home: LlmSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Active provider is already expanded on load — do not tap (that collapses).
    expect(find.textContaining(fullKey), findsNothing);
    expect(find.text('••••••••3W5x'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2)); // base URL + model only
    expect(find.text('Replace key'), findsOneWidget);
  });
}
