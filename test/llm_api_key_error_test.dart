import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/data/llm/openai_client.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

class _StatusHttp implements LlmHttpClient {
  _StatusHttp(this.code);
  final int code;

  @override
  Future<LlmHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    return LlmHttpResponse(statusCode: code, body: '{}');
  }
}

void main() {
  test('OpenAI HTTP errors never include the API key in the message', () async {
    const key = 'sk-super-secret-should-not-leak';
    final client = OpenAiCompatibleAssistClient(http: _StatusHttp(401));
    await expectLater(
      client.complete(
        settings: const LlmSettings(
          provider: LlmProvider.openaiCompatible,
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          apiKey: key,
        ),
        request: const AssistRequest(
          system: 'sys',
          user: 'user',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('401'),
            isNot(contains(key)),
          ),
        ),
      ),
    );

    final tooMany = OpenAiCompatibleAssistClient(http: _StatusHttp(429));
    await expectLater(
      tooMany.complete(
        settings: const LlmSettings(
          provider: LlmProvider.openaiCompatible,
          baseUrl: 'https://api.example.com/v1',
          model: 'gpt-4o-mini',
          apiKey: key,
        ),
        request: const AssistRequest(
          system: 'sys',
          user: 'user',
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('429'),
            isNot(contains(key)),
          ),
        ),
      ),
    );
  });
}
