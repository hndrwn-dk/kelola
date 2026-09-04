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
        system:
            'Explain why this systemd unit failed in plain language. '
            'Ground the answer in the journal and systemctl show fields. '
            'Quote the concrete error line when present. '
            'Suggest one next step. Do not invent facts absent from the input.',
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
        system:
            'Explain what is consuming disk space. '
            'Say what is conventionally safe to remove. Do not invent paths.',
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
