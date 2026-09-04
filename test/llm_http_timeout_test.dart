import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/llm/dart_io_llm_http.dart';

void main() {
  test('Dart HTTP client uses long idle timeout for slow model loads', () {
    expect(
      DartIoLlmHttpClient.idleTimeout,
      greaterThanOrEqualTo(const Duration(minutes: 3)),
    );
    expect(
      DartIoLlmHttpClient.firstRequestTimeout,
      greaterThanOrEqualTo(const Duration(minutes: 3)),
    );
    expect(
      DartIoLlmHttpClient.subsequentRequestTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 90)),
    );
    final client = DartIoLlmHttpClient();
    expect(
      client.currentRequestTimeout,
      DartIoLlmHttpClient.firstRequestTimeout,
    );
  });

  test('source documents first-request timeout for cold Ollama loads', () {
    final src = File('lib/data/llm/dart_io_llm_http.dart').readAsStringSync();
    expect(src, contains('firstRequestTimeout'));
    expect(src, contains('idleTimeout'));
  });
}
