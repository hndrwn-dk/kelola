import 'dart:convert';
import 'dart:io';

import 'package:kelola/data/llm/llm_http.dart';

class DartIoLlmHttpClient implements LlmHttpClient {
  DartIoLlmHttpClient({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = connectionTimeout;
    _client.idleTimeout = idleTimeout;
  }

  final HttpClient _client;
  var _firstRequest = true;

  static const connectionTimeout = Duration(seconds: 30);
  static const idleTimeout = Duration(minutes: 5);
  static const firstRequestTimeout = Duration(minutes: 3);
  static const subsequentRequestTimeout = Duration(seconds: 120);

  Duration get currentRequestTimeout =>
      _firstRequest ? firstRequestTimeout : subsequentRequestTimeout;

  @override
  Future<LlmHttpResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final timeout = currentRequestTimeout;
    _firstRequest = false;
    return _postJson(uri, headers: headers, body: body).timeout(timeout);
  }

  Future<LlmHttpResponse> _postJson(
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
