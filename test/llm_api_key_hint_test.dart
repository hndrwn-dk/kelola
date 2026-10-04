import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/secrets/secret_store.dart';
import 'package:kelola/domain/llm/api_key_hint.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

void main() {
  group('maskLlmApiKeyHint', () {
    test('keys under 12 characters are dots only', () {
      expect(maskLlmApiKeyHint('short'), '••••••••');
      expect(maskLlmApiKeyHint('12345678901'), '••••••••');
      expect(maskLlmApiKeyHint('  sk-tiny  '), '••••••••');
    });

    test('keys 12+ characters keep last 4 after dots', () {
      expect(maskLlmApiKeyHint('sk-abcdefghij3W5x'), '••••••••3W5x');
      expect(maskLlmApiKeyHint('123456789012'), '••••••••9012');
    });
  });

  group('HostRepository apiKeyHint', () {
    test('returns null when no key is stored', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecretStore();
      final repo = HostRepository(db, secrets: secrets);
      expect(await repo.apiKeyHint(LlmProvider.openaiCompatible), isNull);
    });

    test('write persists hint next to the key', () async {
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
            apiKey: 'sk-abcdefghij3W5x',
          ),
        ),
      );
      expect(
        await secrets.read(kLlmOpenaiApiKeyHintSecret),
        '••••••••3W5x',
      );
      expect(
        await repo.apiKeyHint(LlmProvider.openaiCompatible),
        '••••••••3W5x',
      );
      expect(await secrets.read(kLlmOpenaiApiKeySecret), 'sk-abcdefghij3W5x');
    });

    test('legacy key without hint is computed lazily and persisted', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final secrets = MemorySecretStore();
      await secrets.write(kLlmOpenaiApiKeySecret, 'sk-legacy-key-ZZ9q');
      final repo = HostRepository(db, secrets: secrets);
      expect(await secrets.read(kLlmOpenaiApiKeyHintSecret), isNull);
      expect(
        await repo.apiKeyHint(LlmProvider.openaiCompatible),
        '••••••••ZZ9q',
      );
      expect(
        await secrets.read(kLlmOpenaiApiKeyHintSecret),
        '••••••••ZZ9q',
      );
    });

    test('clear removes key and hint', () async {
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
            apiKey: 'sk-abcdefghij3W5x',
          ),
        ),
      );
      await repo.saveLlmSettingsBundle(
        (await repo.loadLlmSettingsBundle()).persistEdit(
          draftProvider: LlmProvider.openaiCompatible,
          draftConfig: const LlmEndpointConfig(
            baseUrl: 'https://api.example.com/v1',
            model: 'gpt-4o-mini',
          ),
        ),
        apiKeyWrite: LlmApiKeyWrite.clear,
      );
      expect(await secrets.read(kLlmOpenaiApiKeySecret), isNull);
      expect(await secrets.read(kLlmOpenaiApiKeyHintSecret), isNull);
      expect(await repo.apiKeyHint(LlmProvider.openaiCompatible), isNull);
    });

    test('keep leaves an existing key untouched when bundle omits it', () async {
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
            apiKey: 'sk-abcdefghij3W5x',
          ),
        ),
      );
      await repo.saveLlmSettingsBundle(
        const LlmSettingsBundle(
          activeProvider: LlmProvider.openaiCompatible,
          openaiCompatible: LlmEndpointConfig(
            baseUrl: 'https://api.example.com/v2',
            model: 'gpt-4o',
          ),
        ),
        apiKeyWrite: LlmApiKeyWrite.keep,
      );
      expect(await secrets.read(kLlmOpenaiApiKeySecret), 'sk-abcdefghij3W5x');
      final bundle = await repo.loadLlmSettingsBundle();
      expect(bundle.openaiCompatible.baseUrl, 'https://api.example.com/v2');
      expect(bundle.openaiCompatible.apiKey, 'sk-abcdefghij3W5x');
    });
  });
}
