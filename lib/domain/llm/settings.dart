import 'package:kelola/domain/llm/provider.dart';

class LlmEndpointConfig {
  const LlmEndpointConfig({
    this.baseUrl,
    this.apiKey,
    this.model,
  });

  static const empty = LlmEndpointConfig();

  final String? baseUrl;
  final String? apiKey;
  final String? model;

  Uri? get baseUri {
    final raw = baseUrl?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  bool get hasValidBaseUrl {
    final uri = baseUri;
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  bool isCompleteFor(LlmProvider provider) {
    if (!provider.enabled) {
      return true;
    }
    if (!hasValidBaseUrl) {
      return false;
    }
    if (model?.trim().isEmpty ?? true) {
      return false;
    }
    if (provider == LlmProvider.openaiCompatible) {
      return apiKey?.trim().isNotEmpty ?? false;
    }
    return true;
  }
}

class LlmSettings {
  const LlmSettings({
    this.provider = LlmProvider.none,
    this.baseUrl,
    this.apiKey,
    this.model,
  });

  final LlmProvider provider;
  final String? baseUrl;
  final String? apiKey;
  final String? model;

  Uri? get baseUri {
    final raw = baseUrl?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uri.tryParse(raw);
  }

  bool get isConfigured {
    return LlmEndpointConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
    ).isCompleteFor(provider);
  }
}

/// Full Assist settings: active provider plus independent endpoint slots.
class LlmSettingsBundle {
  const LlmSettingsBundle({
    this.activeProvider = LlmProvider.none,
    this.ollama = LlmEndpointConfig.empty,
    this.openaiCompatible = LlmEndpointConfig.empty,
  });

  final LlmProvider activeProvider;
  final LlmEndpointConfig ollama;
  final LlmEndpointConfig openaiCompatible;

  LlmEndpointConfig configFor(LlmProvider provider) {
    switch (provider) {
      case LlmProvider.none:
        return LlmEndpointConfig.empty;
      case LlmProvider.ollama:
        return ollama;
      case LlmProvider.openaiCompatible:
        return openaiCompatible;
    }
  }

  LlmSettings get resolved {
    final c = configFor(activeProvider);
    return LlmSettings(
      provider: activeProvider,
      baseUrl: c.baseUrl,
      apiKey: c.apiKey,
      model: c.model,
    );
  }

  /// Persist fields for [draftProvider]. Activates that provider only when
  /// complete (or when draft is [LlmProvider.none]).
  LlmSettingsBundle persistEdit({
    required LlmProvider draftProvider,
    required LlmEndpointConfig draftConfig,
  }) {
    final nextOllama =
        draftProvider == LlmProvider.ollama ? draftConfig : ollama;
    final nextOpenai = draftProvider == LlmProvider.openaiCompatible
        ? draftConfig
        : openaiCompatible;
    final LlmProvider nextActive;
    if (draftProvider == LlmProvider.none) {
      nextActive = LlmProvider.none;
    } else if (draftConfig.isCompleteFor(draftProvider)) {
      nextActive = draftProvider;
    } else {
      nextActive = activeProvider;
    }
    return LlmSettingsBundle(
      activeProvider: nextActive,
      ollama: nextOllama,
      openaiCompatible: nextOpenai,
    );
  }
}

String llmAssistFooterMeta(LlmSettings settings) {
  if (!settings.provider.enabled) {
    return 'LLM · none';
  }
  if (!settings.isConfigured) {
    return 'LLM · not configured';
  }
  switch (settings.provider) {
    case LlmProvider.ollama:
      return 'LLM · ollama';
    case LlmProvider.openaiCompatible:
      return 'LLM · openai';
    case LlmProvider.none:
      return 'LLM · none';
  }
}
