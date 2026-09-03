import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/files/binary_detect.dart';

void main() {
  test('NUL and high control bytes are binary; configs are text', () {
    expect(isBinaryPayload(Uint8List(0)), isFalse);
    expect(isBinaryPayload(Uint8List.fromList(utf8.encode('listen 80;\n'))), isFalse);
    expect(
      isBinaryPayload(Uint8List.fromList(utf8.encode('café · 日本語\n'))),
      isFalse,
    );
    expect(isBinaryPayload(Uint8List.fromList([0x7f, 0x45, 0x4c, 0x46, 0])), isTrue);
    expect(
      isBinaryPayload(Uint8List.fromList(List<int>.filled(64, 1))),
      isTrue,
    );
  });
}
