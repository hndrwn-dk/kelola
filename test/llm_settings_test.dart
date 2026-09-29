import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

void main() {
  group('LlmEndpointConfig', () {
    test('ollama complete needs base URL and model', () {
      expect(
        const LlmEndpointConfig(baseUrl: 'http://192.168.1.5:11434')
            .isCompleteFor(LlmProvider.ollama),
        isFalse,
      );
      expect(
        const LlmEndpointConfig(
          baseUrl: 'http://192.168.1.5:11434',
          model: 'llama3.2',
        ).isCompleteFor(LlmProvider.ollama),
        isTrue,
      );
    });

    test('openai complete needs base URL, model, and API key', () {
      expect(
        const LlmEndpointConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
        ).isCompleteFor(LlmProvider.openaiCompatible),
        isFalse,
      );
      expect(
        const LlmEndpointConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          apiKey: 'sk-test',
        ).isCompleteFor(LlmProvider.openaiCompatible),
        isTrue,
      );
    });

    test('openaiCompatible rejects cleartext HTTP except loopback', () {
      const lan = LlmEndpointConfig(
        baseUrl: 'http://192.168.1.5:8080/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-test',
      );
      expect(lan.isCompleteFor(LlmProvider.openaiCompatible), isFalse);
      expect(lan.hasValidBaseUrlFor(LlmProvider.openaiCompatible), isFalse);

      const loopback = LlmEndpointConfig(
        baseUrl: 'http://127.0.0.1:8080/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-test',
      );
      expect(loopback.isCompleteFor(LlmProvider.openaiCompatible), isTrue);

      const localhost = LlmEndpointConfig(
        baseUrl: 'http://localhost:8080/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-test',
      );
      expect(localhost.isCompleteFor(LlmProvider.openaiCompatible), isTrue);

      expect(
        const LlmEndpointConfig(
          baseUrl: 'http://192.168.1.5:11434',
          model: 'llama3.2',
        ).isCompleteFor(LlmProvider.ollama),
        isTrue,
      );
    });
  });

  group('LlmSettingsBundle', () {
    test('persistEdit keeps provider slots independent and activates only when complete',
        () {
      var bundle = const LlmSettingsBundle();
      bundle = bundle.persistEdit(
        draftProvider: LlmProvider.ollama,
        draftConfig: const LlmEndpointConfig(
          baseUrl: 'http://192.168.18.113:11434',
          model: 'llama3.2:latest',
        ),
      );
      expect(bundle.activeProvider, LlmProvider.ollama);
      expect(bundle.ollama.baseUrl, 'http://192.168.18.113:11434');

      bundle = bundle.persistEdit(
        draftProvider: LlmProvider.openaiCompatible,
        draftConfig: const LlmEndpointConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          // missing key — draft saved, active stays ollama
        ),
      );
      expect(bundle.activeProvider, LlmProvider.ollama);
      expect(bundle.openaiCompatible.baseUrl, 'https://api.example.com/v1');
      expect(bundle.ollama.model, 'llama3.2:latest');

      bundle = bundle.persistEdit(
        draftProvider: LlmProvider.openaiCompatible,
        draftConfig: const LlmEndpointConfig(
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          apiKey: 'sk-live',
        ),
      );
      expect(bundle.activeProvider, LlmProvider.openaiCompatible);
      expect(bundle.resolved.apiKey, 'sk-live');
      expect(bundle.ollama.baseUrl, 'http://192.168.18.113:11434');
    });

    test('footer meta reflects active provider', () {
      expect(llmAssistFooterMeta(const LlmSettings()), 'set up');
      expect(
        llmAssistFooterMeta(
          const LlmSettings(
            provider: LlmProvider.ollama,
            baseUrl: 'http://127.0.0.1:11434',
            model: 'llama3.2',
          ),
        ),
        'ollama · llama3.2',
      );
      expect(
        llmAssistFooterMeta(
          const LlmSettings(
            provider: LlmProvider.openaiCompatible,
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-4o-mini',
            apiKey: 'sk',
          ),
        ),
        'openai · gpt-4o-mini',
      );
      expect(
        llmAssistFooterMeta(
          const LlmSettings(
            provider: LlmProvider.ollama,
            baseUrl: 'http://127.0.0.1:11434',
          ),
        ),
        'set up',
      );
    });
  });

  group('HostRepository LLM persistence', () {
    test('fresh install LLM provider defaults to none', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final settings = await repo.loadLlmSettings();
      expect(settings.provider, LlmProvider.none);
      expect(settings.baseUrl, isNull);
      expect(settings.apiKey, isNull);
    });

    test('ollama and openai configs persist independently', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);

      await repo.saveLlmSettingsBundle(
        const LlmSettingsBundle().persistEdit(
          draftProvider: LlmProvider.ollama,
          draftConfig: LlmEndpointConfig(
            baseUrl: 'http://192.168.18.113:11434',
            model: 'llama3.2:latest',
          ),
        ),
      );
      await repo.saveLlmSettingsBundle(
        (await repo.loadLlmSettingsBundle()).persistEdit(
          draftProvider: LlmProvider.openaiCompatible,
          draftConfig: const LlmEndpointConfig(
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-4o-mini',
            apiKey: 'sk-test',
          ),
        ),
      );

      final bundle = await repo.loadLlmSettingsBundle();
      expect(bundle.activeProvider, LlmProvider.openaiCompatible);
      expect(bundle.ollama.baseUrl, 'http://192.168.18.113:11434');
      expect(bundle.ollama.model, 'llama3.2:latest');
      expect(bundle.openaiCompatible.apiKey, 'sk-test');

      await repo.saveLlmSettingsBundle(
        bundle.persistEdit(
          draftProvider: LlmProvider.ollama,
          draftConfig: bundle.ollama,
        ),
      );
      final back = await repo.loadLlmSettingsBundle();
      expect(back.activeProvider, LlmProvider.ollama);
      expect(back.openaiCompatible.baseUrl, 'https://api.example.com/v1');
      expect(back.resolved.model, 'llama3.2:latest');
    });

    test('openai api key is not written to sqlite', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      await repo.saveLlmSettingsBundle(
        const LlmSettingsBundle().persistEdit(
          draftProvider: LlmProvider.openaiCompatible,
          draftConfig: const LlmEndpointConfig(
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-4o-mini',
            apiKey: 'sk-secret',
          ),
        ),
      );

      final row = await (db.select(db.appSettings)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(row.llmOpenaiApiKey, isNull);
      expect(row.llmApiKey, isNull);
      expect(
        (await repo.loadLlmSettingsBundle()).openaiCompatible.apiKey,
        'sk-secret',
      );
    });

    test('leftover sqlite openai key is migrated and wiped', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      await db.into(db.appSettings).insertOnConflictUpdate(
            const AppSettingsCompanion(
              id: Value(1),
              llmOpenaiApiKey: Value('sk-old'),
            ),
          );
      final repo = HostRepository(db);
      expect(
        (await repo.loadLlmSettingsBundle()).openaiCompatible.apiKey,
        'sk-old',
      );
      final row = await (db.select(db.appSettings)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(row.llmOpenaiApiKey, isNull);
      expect(row.llmApiKey, isNull);
    });
  });
}
