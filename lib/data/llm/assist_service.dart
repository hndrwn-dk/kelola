import 'package:kelola/data/llm/assist_client.dart';
import 'package:kelola/data/llm/llm_http.dart';
import 'package:kelola/data/llm/ollama_client.dart';
import 'package:kelola/data/llm/openai_client.dart';
import 'package:kelola/domain/llm/assist_context.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/catalog.dart';
import 'package:kelola/domain/llm/preview_gate.dart';
import 'package:kelola/domain/llm/propose.dart';
import 'package:kelola/domain/llm/provider.dart';
import 'package:kelola/domain/llm/settings.dart';

class AssistPreview {
  const AssistPreview({required this.system, required this.user});

  final String system;
  final String user;
}

class AssistService {
  AssistService({
    required LlmHttpClient http,
    AssistPreviewGate? gate,
  })  : _http = http,
        gate = gate ?? AssistPreviewGate();

  /// Mobile incident sheet: keep replies scannable.
  static const failedUnitSystemPrompt =
      'Explain why this systemd unit failed in plain language. '
      'Reply with at most 3 short paragraphs: (1) the cause, '
      '(2) quote the concrete error line when present, '
      '(3) one next step. '
      'Ground the answer in the journal and systemctl show fields. '
      'Do not invent facts absent from the input. Do not repeat yourself.';

  static const diskSystemPrompt =
      'Explain what is consuming disk space. '
      'Reply with at most 3 short paragraphs: (1) what is large, '
      '(2) evidence from df/du, (3) one conventionally safe next step. '
      'Do not invent paths.';

  final LlmHttpClient _http;
  final AssistPreviewGate gate;

  AssistPreview previewPayload(AssistRequest request) {
    final r = redactAssistPayload(request);
    return AssistPreview(system: r.system, user: r.user);
  }

  bool needsCloudPreview(LlmSettings settings) =>
      gate.needsPreview(settings.provider);

  void approveCloudPreview() => gate.markCloudApproved();

  Future<String> explainFailedUnit({
    required LlmSettings settings,
    required String unitName,
    required String showOutput,
    required String journal,
    required List<String> hostnames,
    required List<String> usernames,
  }) {
    return _complete(
      settings: settings,
      request: AssistRequest(
        system: failedUnitSystemPrompt,
        user:
            'Unit: $unitName\n\n--- show ---\n$showOutput\n\n--- journal ---\n$journal',
        hostnames: hostnames,
        usernames: usernames,
      ),
    );
  }

  Future<String> explainDisk({
    required LlmSettings settings,
    required String dfOutput,
    required String duOutput,
    required List<String> hostnames,
    required List<String> usernames,
  }) {
    return _complete(
      settings: settings,
      request: AssistRequest(
        system: diskSystemPrompt,
        user: '--- df ---\n$dfOutput\n\n--- du ---\n$duOutput',
        hostnames: hostnames,
        usernames: usernames,
      ),
    );
  }

  Future<String> summariseLogs({
    required LlmSettings settings,
    required String logs,
    required List<String> hostnames,
    required List<String> usernames,
  }) {
    return _complete(
      settings: settings,
      request: AssistRequest(
        system: 'Summarise these journal lines briefly. Do not invent events.',
        user: logs,
        hostnames: hostnames,
        usernames: usernames,
      ),
    );
  }

  Future<ProbeProposal> proposeFromIntent({
    required LlmSettings settings,
    required String intent,
    required AssistContext context,
    required List<String> hostnames,
    required List<String> usernames,
  }) async {
    final raw = await _complete(
      settings: settings,
      request: AssistRequest(
        system:
            'Map the user intent to one catalog action. '
            'Only use units/paths listed in context. '
            '${catalogPromptBlock()}\n'
            'Context units: ${context.unitNames.join(', ')}\n'
            'Context paths: ${context.paths.join(', ')}',
        user: intent,
        hostnames: hostnames,
        usernames: usernames,
      ),
    );
    return parseProbeProposal(
      raw,
      catalog: assistCatalog,
      context: context,
    );
  }

  Future<String> _complete({
    required LlmSettings settings,
    required AssistRequest request,
  }) {
    if (!settings.provider.enabled || !settings.isConfigured) {
      throw StateError('Assist provider is not configured');
    }
    if (needsCloudPreview(settings)) {
      throw StateError('Cloud preview not approved');
    }
    return _clientFor(settings.provider).complete(
      settings: settings,
      request: request,
    );
  }

  AssistModelClient _clientFor(LlmProvider provider) {
    switch (provider) {
      case LlmProvider.ollama:
        return OllamaAssistClient(http: _http);
      case LlmProvider.openaiCompatible:
        return OpenAiCompatibleAssistClient(http: _http);
      case LlmProvider.none:
        throw StateError('Assist provider is none');
    }
  }
}
