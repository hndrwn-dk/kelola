import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/domain/redaction/redact.dart';

/// Always redact before any provider sees the payload — including Ollama.
({String system, String user}) redactAssistPayload(AssistRequest request) {
  return (
    system: redactText(
      request.system,
      hostnames: request.hostnames,
      usernames: request.usernames,
    ),
    user: redactText(
      request.user,
      hostnames: request.hostnames,
      usernames: request.usernames,
    ),
  );
}

abstract class AssistModelClient {
  Future<String> complete({
    required LlmSettings settings,
    required AssistRequest request,
  });
}
