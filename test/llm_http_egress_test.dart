import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/domain/llm/provider.dart';

void main() {
  test('fake client throws when authority is not the configured base', () async {
    final client = RecordingLlmHttpClient(
      allowedBase: Uri.parse('http://192.168.1.50:11434'),
    );
    await expectLater(
      client.postJson(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: const {},
        body: '{"x":1}',
      ),
      throwsA(isA<LlmEgressViolation>()),
    );
    expect(client.bodies, isEmpty);
  });

  test('fake client accepts only the configured Ollama base', () async {
    final base = Uri.parse('http://10.0.0.2:11434');
    final client = RecordingLlmHttpClient(allowedBase: base);
    final res = await client.postJson(
      base.replace(path: '/api/chat'),
      headers: const {'content-type': 'application/json'},
      body: '{}',
    );
    expect(res.statusCode, 200);
    expect(client.uris.single.host, '10.0.0.2');
  });

  test('provider default is none', () {
    expect(LlmProvider.defaultValue, LlmProvider.none);
    expect(LlmProvider.parse(null), LlmProvider.none);
    expect(LlmProvider.parse(''), LlmProvider.none);
  });
}
