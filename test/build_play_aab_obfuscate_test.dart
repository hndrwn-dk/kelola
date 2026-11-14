import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Play AAB build is obfuscated and keeps its symbols', () {
    final src = File('scripts/build_play_aab.sh').readAsStringSync();
    expect(src, contains('  --obfuscate \\'));
    expect(src, contains('--split-debug-info="\$SYMBOLS"'));
    expect(src, contains('release builds are always obfuscated'));
  });
}
