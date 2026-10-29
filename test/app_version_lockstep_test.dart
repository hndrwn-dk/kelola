import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app_version.dart';

void main() {
  test('app_version defaults match pubspec version name and +build', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final raw = line.substring('version:'.length).trim();
    final parts = raw.split('+');
    expect(parts, hasLength(2), reason: 'pubspec version must be name+build');
    expect(kelolaAppVersion, parts[0]);
    expect(kelolaVersionCode, parts[1]);
  });

  test('CI and local AAB builds inject the same defines the Settings row reads',
      () {
    final workflow = File('.github/workflows/app.yml').readAsStringSync();
    expect(workflow, contains('--dart-define=KELOLA_VERSION='));
    expect(workflow, contains('--dart-define=KELOLA_BUILD='));
    expect(workflow, contains('--build-number='));

    final wrap = File('scripts/build_play_aab.sh').readAsStringSync();
    expect(wrap, contains('--dart-define=KELOLA_VERSION='));
    expect(wrap, contains('--dart-define=KELOLA_BUILD='));
  });
}
