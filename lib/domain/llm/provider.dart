enum LlmProvider {
  none,
  ollama,
  openaiCompatible;

  static const defaultValue = LlmProvider.none;

  static LlmProvider parse(String? raw) {
    switch ((raw ?? '').trim()) {
      case 'ollama':
        return LlmProvider.ollama;
      case 'openaiCompatible':
      case 'openai':
        return LlmProvider.openaiCompatible;
      default:
        return LlmProvider.none;
    }
  }

  String get storageName => name;

  bool get isLocalClaim => this == LlmProvider.ollama;

  bool get needsCloudPreview => this == LlmProvider.openaiCompatible;

  bool get enabled => this != LlmProvider.none;
}
