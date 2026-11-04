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

  test('local AAB build injects the same defines the Settings row reads', () {
    final wrap = File('scripts/build_play_aab.sh').readAsStringSync();
    expect(wrap, contains('--build-name="\$VERSION_NAME"'));
    expect(wrap, contains('--build-number="\$VERSION_CODE"'));
    expect(wrap, contains('--dart-define=KELOLA_VERSION="\$VERSION_NAME"'));
    expect(wrap, contains('--dart-define=KELOLA_BUILD="\$VERSION_CODE"'));
    // What's new card: release builds only, name without +build.
    expect(wrap, contains('--dart-define=APP_VERSION="\$VERSION_NAME"'));
    expect(wrap, contains('--dart-define=APP_VERSION*'));
    // No second versionCode source: overrides are refused.
    expect(wrap, contains('--build-number*|--build-name*'));
    expect(wrap, contains('--dart-define-from-file*'));
    // The space form `--dart-define KELOLA_BUILD=…` is refused too.
    expect(
      wrap,
      contains(
        '"\$prev" == "--dart-define" && ( "\$arg" == KELOLA_* || "\$arg" == APP_VERSION* )',
      ),
    );
  });

  test('CI never builds or uploads a Play AAB', () {
    final workflow = File('.github/workflows/app.yml').readAsStringSync();
    expect(workflow, isNot(contains('flutter build appbundle')));
    expect(workflow, isNot(contains('upload-google-play')));
    expect(workflow, isNot(contains('GITHUB_RUN_NUMBER')));
    expect(workflow, isNot(contains('play_track')));
    expect(workflow, contains('versionCode +'));
  });
}
