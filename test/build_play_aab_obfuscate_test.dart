import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Play AAB build is obfuscated and keeps its symbols', () {
    final src = File('scripts/build_play_aab.sh').readAsStringSync();
    expect(src, contains('  --obfuscate \\'));
    expect(src, contains('--split-debug-info="\$SYMBOLS"'));
    expect(src, contains('release builds are always obfuscated'));
  });

  test('Play AAB build puts the release notes next to the AAB', () {
    final src = File('scripts/build_play_aab.sh').readAsStringSync();
    expect(
      src,
      contains(
        'cp -f "\$ROOT/docs/store/whatsnew/whatsnew-en-US" '
        '"\$DEST/whatsnew-en-US.txt"',
      ),
    );
    expect(src, isNot(contains('play-console/PLAY_STORE_v')));
  });
}
