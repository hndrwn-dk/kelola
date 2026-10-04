/// Masked API-key hint for UI. Never returns the full key.
///
/// Keys shorter than 12 characters (after trim) are dots only. Longer keys
/// keep the last 4 characters after eight bullets.
String maskLlmApiKeyHint(String key) {
  final trimmed = key.trim();
  if (trimmed.length < 12) {
    return '••••••••';
  }
  return '••••••••${trimmed.substring(trimmed.length - 4)}';
}

enum LlmApiKeyWrite {
  /// Write [LlmEndpointConfig.apiKey] (empty clears the secret).
  set,

  /// Leave the stored secret and hint unchanged.
  keep,

  /// Delete the stored secret and hint.
  clear,
}
