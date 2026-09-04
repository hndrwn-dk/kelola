class LlmHttpResponse {
  const LlmHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class LlmEgressViolation implements Exception {
  LlmEgressViolation(this.uri);

  final Uri uri;

  @override
  String toString() => 'LLM egress refused for $uri';
}

abstract class LlmHttpClient {
  Future<LlmHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  });
}

/// Test double: only the configured base authority is allowed.
class RecordingLlmHttpClient implements LlmHttpClient {
  RecordingLlmHttpClient({
    required this.allowedBase,
    this.responseBody = '{}',
    this.statusCode = 200,
  });

  final Uri allowedBase;
  final String responseBody;
  final int statusCode;
  final bodies = <String>[];
  final uris = <Uri>[];

  @override
  Future<LlmHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    if (uri.scheme != allowedBase.scheme ||
        uri.host != allowedBase.host ||
        uri.port != allowedBase.port) {
      throw LlmEgressViolation(uri);
    }
    uris.add(uri);
    bodies.add(body);
    return LlmHttpResponse(statusCode: statusCode, body: responseBody);
  }
}
