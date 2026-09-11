import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/preview_gate.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

LlmSettings _ollama(String baseUrl) => LlmSettings(
      provider: LlmProvider.ollama,
      baseUrl: baseUrl,
      model: 'llama',
    );

LlmSettings _openai(String baseUrl) => LlmSettings(
      provider: LlmProvider.openaiCompatible,
      baseUrl: baseUrl,
      model: 'gpt',
      apiKey: 'sk-test',
    );

void main() {
  group('AssistPreviewGate', () {
    test('Ollama + local endpoint → no preview (lab regression)', () {
      final gate = AssistPreviewGate();
      expect(gate.needsPreview(_ollama('http://192.168.1.50:11434')), isFalse);
      expect(gate.needsPreview(_ollama('http://10.0.2.2:11434')), isFalse);
      expect(gate.needsPreview(_ollama('http://100.64.1.2:11434')), isFalse);
    });

    test('Ollama + public endpoint → preview; approve clears for same key', () {
      final gate = AssistPreviewGate();
      final settings = _ollama('http://203.0.113.10:11434');
      expect(gate.needsPreview(settings), isTrue);
      gate.markApproved(settings);
      expect(gate.needsPreview(settings), isFalse);
    });

    test('OpenAI-compatible + local endpoint → still preview (monotonic)', () {
      final gate = AssistPreviewGate();
      final settings = _openai('http://192.168.1.50:8080');
      expect(gate.needsPreview(settings), isTrue);
      gate.markApproved(settings);
      expect(gate.needsPreview(settings), isFalse);
    });

    test('OpenAI-compatible + public endpoint → preview', () {
      final gate = AssistPreviewGate();
      expect(
        gate.needsPreview(_openai('https://api.openai.com/v1')),
        isTrue,
      );
    });

    test('approving endpoint A does not approve endpoint B', () {
      final gate = AssistPreviewGate();
      final a = _ollama('http://203.0.113.10:11434');
      final b = _ollama('http://198.51.100.20:11434');
      gate.markApproved(a);
      expect(gate.needsPreview(a), isFalse);
      expect(gate.needsPreview(b), isTrue);
    });

    test('approving OpenAI does not approve public Ollama', () {
      final gate = AssistPreviewGate();
      final cloud = _openai('https://api.openai.com/v1');
      final publicOllama = _ollama('http://203.0.113.10:11434');
      gate.markApproved(cloud);
      expect(gate.needsPreview(cloud), isFalse);
      expect(gate.needsPreview(publicOllama), isTrue);
    });
  });

  group('AssistService preview guard', () {
    test('unapproved public Ollama throws Preview not approved', () {
      final service = AssistService(
        http: RecordingLlmHttpClient(
          allowedBase: Uri.parse('http://203.0.113.10:11434'),
        ),
      );
      expect(
        () => service.explainFailedUnit(
          settings: _ollama('http://203.0.113.10:11434'),
          unitName: 'nginx.service',
          showOutput: 'ActiveState=failed',
          journal: 'fail',
          hostnames: const [],
          usernames: const [],
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Preview not approved',
          ),
        ),
      );
    });

    test('needsPreview / approvePreview mirror the gate', () {
      final gate = AssistPreviewGate();
      final service = AssistService(
        http: RecordingLlmHttpClient(
          allowedBase: Uri.parse('http://203.0.113.10:11434'),
        ),
        gate: gate,
      );
      final settings = _ollama('http://203.0.113.10:11434');
      expect(service.needsPreview(settings), isTrue);
      service.approvePreview(settings);
      expect(service.needsPreview(settings), isFalse);
    });

    test('previewPayload still redacts without requiring approval', () {
      final service = AssistService(
        http: RecordingLlmHttpClient(
          allowedBase: Uri.parse('http://127.0.0.1:11434'),
        ),
      );
      final preview = service.previewPayload(
        const AssistRequest(
          system: 'sys',
          user: 'user nas-01',
          hostnames: ['nas-01'],
          usernames: [],
        ),
      );
      expect(preview.user, isNot(contains('nas-01')));
    });
  });
}
