import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/data/llm/ollama_client.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

void main() {
  test('payload that reaches the HTTP client is already redacted', () async {
    final http = RecordingLlmHttpClient(
      allowedBase: Uri.parse('http://127.0.0.1:11434'),
      responseBody: '{"message":{"content":"ok"}}',
    );
    final client = OllamaAssistClient(http: http);
    final settings = LlmSettings(
      provider: LlmProvider.ollama,
      baseUrl: 'http://127.0.0.1:11434',
      model: 'llama3.2',
    );
    await client.complete(
      settings: settings,
      request: AssistRequest(
        system: 'You help.',
        user: 'Host nas-01 at 10.0.0.8 user ops password=s3cret',
        hostnames: const ['nas-01'],
        usernames: const ['ops'],
      ),
    );
    expect(http.bodies, hasLength(1));
    final body = http.bodies.single;
    expect(body, isNot(contains('10.0.0.8')));
    expect(body, isNot(contains('nas-01')));
    expect(body, isNot(contains('ops')));
    expect(body, isNot(contains('s3cret')));
    expect(body, contains('<IP_'));
    expect(body, contains('<HOST_'));
    expect(body, contains('<USER_'));
    expect(body, contains('<REDACTED>'));
  });
}
