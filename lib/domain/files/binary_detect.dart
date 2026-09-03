import 'dart:typed_data';

import 'package:kelola/domain/exceptions.dart';

bool isBinaryPayload(List<int> bytes) {
  final n = bytes.length < 8192 ? bytes.length : 8192;
  if (n == 0) {
    return false;
  }
  var controls = 0;
  for (var i = 0; i < n; i++) {
    final b = bytes[i];
    if (b == 0) {
      return true;
    }
    if (b < 32 && b != 9 && b != 10 && b != 13) {
      controls++;
    }
  }
  return controls / n > 0.30;
}

void prepareTextEdit(List<int> peek) {
  final payload = peek is Uint8List ? peek : Uint8List.fromList(peek);
  if (isBinaryPayload(payload)) {
    throw BinaryFileException();
  }
}
