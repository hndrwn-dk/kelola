import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final root = Directory.current.path;
  final script = File(p.join(root, 'scripts', 'check_play_billing.dart'));
  final wrapper = File(p.join(root, 'scripts', 'build_play_aab.sh'));
  final checkSh = File(p.join(root, 'scripts', 'check_play_billing.sh'));

  test('play billing gate scripts exist and build_play_aab invokes check', () {
    expect(script.existsSync(), isTrue);
    expect(wrapper.existsSync(), isTrue);
    expect(checkSh.existsSync(), isTrue);
    final wrap = wrapper.readAsStringSync();
    expect(wrap, contains('check_play_billing'));
    expect(wrap, contains('flutter build appbundle --release'));
    expect(wrap, contains('bundles_release'));
    expect(wrap, contains('app-release-'));
    // Gate runs before build; set -e means a check failure aborts the AAB.
    expect(wrap, contains('set -euo pipefail'));
  });

  test('tracked Play notes point at bundles_release, not build/outputs', () {
    final dir = Directory(p.join(root, 'docs', 'play'));
    final notes = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('release-notes-'));
    expect(notes, isNotEmpty);
    for (final file in notes) {
      final src = file.readAsStringSync();
      expect(
        src,
        contains('bundles_release/'),
        reason: '${file.path} must store the AAB under bundles_release',
      );
      expect(
        src,
        isNot(contains('build/app/outputs/bundle')),
        reason: '${file.path} must not treat Gradle output as the release store',
      );
    }
  });

  test('build_play_aab.sh refuses without pubspec_overrides.yaml', () {
    final sandbox = _makeGateSandbox();
    addTearDown(() => _deleteQuiet(sandbox));

    final result = Process.runSync(
      'bash',
      ['scripts/build_play_aab.sh'],
      workingDirectory: sandbox.path,
      runInShell: true,
    );
    expect(result.exitCode, isNot(0),
        reason: 'must not proceed to flutter build appbundle');
    final out = '${result.stdout}${result.stderr}';
    expect(out, contains('pubspec_overrides.yaml'));
    expect(out, isNot(contains('Running Gradle')),
        reason: 'flutter build must not have started');
  });

  test('check_play_billing accepts a non-stub override path', () {
    final sandbox = _makeGateSandbox();
    addTearDown(() => _deleteQuiet(sandbox));

    final fakeRoot = Directory.systemTemp.createTempSync('kelola_pro_gate_');
    addTearDown(() => _deleteQuiet(fakeRoot));

    final stub = Directory(p.join(sandbox.path, 'packages', 'kelola_pro'));
    final fakePro = Directory(p.join(fakeRoot.path, 'kelola_pro'));
    _copyDir(stub, fakePro);

    // Use forward slashes so YAML path works on Windows bash/Dart alike.
    final fakePath = fakePro.path.replaceAll(r'\', '/');
    File(p.join(sandbox.path, 'pubspec_overrides.yaml')).writeAsStringSync(
      'dependency_overrides:\n'
      '  kelola_pro:\n'
      '    path: $fakePath\n',
    );

    final result = Process.runSync(
      'bash',
      ['scripts/check_play_billing.sh'],
      workingDirectory: sandbox.path,
      runInShell: true,
    );
    expect(result.exitCode, 0,
        reason: '${result.stdout}${result.stderr}');
    expect(
      '${result.stdout}${result.stderr}',
      contains('check_play_billing: ok'),
    );
  });

  test('check_play_billing rejects override that still points at stub', () {
    final sandbox = _makeGateSandbox();
    addTearDown(() => _deleteQuiet(sandbox));

    File(p.join(sandbox.path, 'pubspec_overrides.yaml')).writeAsStringSync(
      'dependency_overrides:\n'
      '  kelola_pro:\n'
      '    path: packages/kelola_pro\n',
    );

    final result = Process.runSync(
      'bash',
      ['scripts/check_play_billing.sh'],
      workingDirectory: sandbox.path,
      runInShell: true,
    );
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('packages/kelola_pro'),
    );
  });
}

/// Minimal checkout under [Directory.systemTemp]. Never copies the developer's
/// root [pubspec_overrides.yaml], so local billing wiring stays untouched.
Directory _makeGateSandbox() {
  final root = Directory.current.path;
  final sandbox = Directory.systemTemp.createTempSync('kelola_billing_gate_');
  File(p.join(root, 'pubspec.yaml')).copySync(
    p.join(sandbox.path, 'pubspec.yaml'),
  );
  _copyDir(
    Directory(p.join(root, 'packages', 'kelola_pro')),
    Directory(p.join(sandbox.path, 'packages', 'kelola_pro')),
  );
  final scripts = Directory(p.join(sandbox.path, 'scripts'))
    ..createSync(recursive: true);
  for (final name in [
    'check_play_billing.dart',
    'check_play_billing.sh',
    'build_play_aab.sh',
  ]) {
    File(p.join(root, 'scripts', name)).copySync(p.join(scripts.path, name));
  }
  return sandbox;
}

void _deleteQuiet(Directory dir) {
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

void _copyDir(Directory src, Directory dst) {
  dst.createSync(recursive: true);
  for (final entity in src.listSync(recursive: true)) {
    final rel = p.relative(entity.path, from: src.path);
    final target = p.join(dst.path, rel);
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entity.readAsBytesSync());
    }
  }
}
