import 'dart:convert';

import 'package:kelola/data/llm/assist_client.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/settings.dart';

class OllamaAssistClient implements AssistModelClient {
  OllamaAssistClient({required this.http});

  final LlmHttpClient http;

  @override
  Future<String> complete({
    required LlmSettings settings,
    required AssistRequest request,
  }) async {
    final base = settings.baseUri;
    if (base == null) {
      throw StateError('Ollama base URL missing');
    }
    final redacted = redactAssistPayload(request);
    final model = (settings.model?.trim().isNotEmpty ?? false)
        ? settings.model!.trim()
        : 'llama3.2';
    final uri = base.replace(
      path: _join(base.path, 'api/chat'),
    );
    final body = jsonEncode({
      'model': model,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': redacted.system},
        {'role': 'user', 'content': redacted.user},
      ],
    });
    final res = await http.postJson(
      uri,
      headers: const {'content-type': 'application/json'},
      body: body,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw StateError('Ollama HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is Map && message['content'] is String) {
        return message['content'] as String;
      }
      final content = decoded['response'];
      if (content is String) {
        return content;
      }
    }
    return res.body;
  }
}

String _join(String basePath, String suffix) {
  final a = basePath.endsWith('/') ? basePath.substring(0, basePath.length - 1) : basePath;
  if (a.isEmpty || a == '/') {
    return '/$suffix';
  }
  return '$a/$suffix';
}
