import 'dart:convert';

import 'package:kelola/data/llm/assist_client.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/settings.dart';

class OpenAiCompatibleAssistClient implements AssistModelClient {
  OpenAiCompatibleAssistClient({required this.http});

  final LlmHttpClient http;

  @override
  Future<String> complete({
    required LlmSettings settings,
    required AssistRequest request,
  }) async {
    final base = settings.baseUri;
    final key = settings.apiKey?.trim() ?? '';
    if (base == null || key.isEmpty) {
      throw StateError('OpenAI-compatible settings incomplete');
    }
    final redacted = redactAssistPayload(request);
    final model = (settings.model?.trim().isNotEmpty ?? false)
        ? settings.model!.trim()
        : 'gpt-4o-mini';
    final uri = base.replace(
      path: _join(base.path, 'v1/chat/completions'),
    );
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': redacted.system},
        {'role': 'user', 'content': redacted.user},
      ],
    });
    final res = await http.postJson(
      uri,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $key',
      },
      body: body,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('OpenAI-compatible HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map) {
          final message = first['message'];
          if (message is Map && message['content'] is String) {
            return message['content'] as String;
          }
        }
      }
    }
    return res.body;
  }
}

String _join(String basePath, String suffix) {
  final a = basePath.endsWith('/')
      ? basePath.substring(0, basePath.length - 1)
      : basePath;
  if (a.isEmpty || a == '/') {
    return '/$suffix';
  }
  return '$a/$suffix';
}
