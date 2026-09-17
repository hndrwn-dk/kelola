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
    // Gate runs before build; set -e means a check failure aborts the AAB.
    expect(wrap, contains('set -euo pipefail'));
  });

  test('build_play_aab.sh refuses without pubspec_overrides.yaml', () {
    final overrides = File(p.join(root, 'pubspec_overrides.yaml'));
    expect(overrides.existsSync(), isFalse,
        reason: 'test assumes no overrides in CI/dev checkout');
    final result = Process.runSync(
      'bash',
      ['scripts/build_play_aab.sh'],
      workingDirectory: root,
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
    final overrides = File(p.join(root, 'pubspec_overrides.yaml'));
    expect(overrides.existsSync(), isFalse);

    final fakeRoot = Directory.systemTemp.createTempSync('kelola_pro_gate_');
    addTearDown(() {
      if (overrides.existsSync()) {
        overrides.deleteSync();
      }
      Process.runSync(
        'flutter',
        ['pub', 'get'],
        workingDirectory: root,
        runInShell: true,
      );
      if (fakeRoot.existsSync()) {
        fakeRoot.deleteSync(recursive: true);
      }
    });

    final stub = Directory(p.join(root, 'packages', 'kelola_pro'));
    final fakePro = Directory(p.join(fakeRoot.path, 'kelola_pro'));
    _copyDir(stub, fakePro);

    // Use forward slashes so YAML path works on Windows bash/Dart alike.
    final fakePath = fakePro.path.replaceAll(r'\', '/');
    overrides.writeAsStringSync(
      'dependency_overrides:\n'
      '  kelola_pro:\n'
      '    path: $fakePath\n',
    );

    final result = Process.runSync(
      'bash',
      ['scripts/check_play_billing.sh'],
      workingDirectory: root,
      runInShell: true,
    );
    expect(result.exitCode, 0,
        reason: '${result.stdout}${result.stderr}');
    expect('${result.stdout}${result.stderr}', contains('check_play_billing: ok'));
  });

  test('check_play_billing rejects override that still points at stub', () {
    final overrides = File(p.join(root, 'pubspec_overrides.yaml'));
    expect(overrides.existsSync(), isFalse);
    addTearDown(() {
      if (overrides.existsSync()) {
        overrides.deleteSync();
      }
      Process.runSync(
        'flutter',
        ['pub', 'get'],
        workingDirectory: root,
        runInShell: true,
      );
    });

    overrides.writeAsStringSync(
      'dependency_overrides:\n'
      '  kelola_pro:\n'
      '    path: packages/kelola_pro\n',
    );

    final result = Process.runSync(
      'bash',
      ['scripts/check_play_billing.sh'],
      workingDirectory: root,
      runInShell: true,
    );
    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('packages/kelola_pro'),
    );
  });
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
