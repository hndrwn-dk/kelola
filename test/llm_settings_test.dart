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
      expect(llmAssistFooterMeta(const LlmSettings()), 'LLM · none');
      expect(
        llmAssistFooterMeta(
          const LlmSettings(
            provider: LlmProvider.ollama,
            baseUrl: 'http://127.0.0.1:11434',
            model: 'llama3.2',
          ),
        ),
        'LLM · ollama',
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
        'LLM · openai',
      );
      expect(
        llmAssistFooterMeta(
          const LlmSettings(
            provider: LlmProvider.ollama,
            baseUrl: 'http://127.0.0.1:11434',
          ),
        ),
        'LLM · not configured',
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
  });
}
