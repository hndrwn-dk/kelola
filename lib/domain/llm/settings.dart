import 'package:kelola/domain/llm/provider.dart';

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
    if (!provider.enabled) {
      return false;
    }
    final uri = baseUri;
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return false;
    }
    if (provider == LlmProvider.openaiCompatible) {
      final key = apiKey?.trim() ?? '';
      if (key.isEmpty) {
        return false;
      }
    }
    return true;
  }
}
