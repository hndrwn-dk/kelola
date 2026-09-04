import 'dart:convert';
import 'dart:io';

import 'package:kelola/data/llm/llm_http.dart';

class DartIoLlmHttpClient implements LlmHttpClient {
  DartIoLlmHttpClient({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  Future<LlmHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final req = await _client.postUrl(uri);
    headers.forEach(req.headers.set);
    req.headers.contentType = ContentType.json;
    req.write(body);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return LlmHttpResponse(statusCode: res.statusCode, body: text);
  }
}
