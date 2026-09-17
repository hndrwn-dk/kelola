#!/usr/bin/env dart
// Refuse a Play release AAB unless kelola_pro resolves outside the in-repo
// OpenEntitlement stub (sourceLabel "std", all Pro unlocked).
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final root = Directory.current.absolute;
  final overrides = File('${root.path}/pubspec_overrides.yaml');
  final stub = Directory('${root.path}/packages/kelola_pro').absolute;

  if (!overrides.existsSync()) {
    _die(
      'pubspec_overrides.yaml is missing. A release AAB would ship the std '
      'stub (all Pro unlocked). Point kelola_pro at the private billing package.',
    );
  }

  final overrideSrc = overrides.readAsStringSync();
  if (!RegExp(r'^\s*kelola_pro\s*:', multiLine: true).hasMatch(overrideSrc)) {
    _die('pubspec_overrides.yaml does not override kelola_pro.');
  }

  // dependency_overrides must not keep the public stub path.
  final block = RegExp(
    r'^\s*kelola_pro\s*:.*(?:\n[ \t]+.+)*',
    multiLine: true,
  ).firstMatch(overrideSrc)?.group(0) ?? '';
  if (block.contains('packages/kelola_pro')) {
    _die('kelola_pro override still points at packages/kelola_pro (the std stub).');
  }

  final pub = Process.runSync(
    'flutter',
    ['pub', 'get'],
    workingDirectory: root.path,
    runInShell: true,
  );
  if (pub.exitCode != 0) {
    stderr.write(pub.stderr);
    _die('flutter pub get failed.');
  }

  final configFile = File('${root.path}/.dart_tool/package_config.json');
  if (!configFile.existsSync()) {
    _die('package_config.json missing after pub get.');
  }

  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  Map<String, dynamic>? hit;
  for (final p in packages) {
    final m = p as Map<String, dynamic>;
    if (m['name'] == 'kelola_pro') {
      hit = m;
      break;
    }
  }
  if (hit == null) {
    _die('kelola_pro missing from package_config.json.');
  }

  final rootUri = hit!['rootUri'] as String;
  final resolved =
      Directory.fromUri(configFile.parent.uri.resolve(rootUri)).absolute;
  final stubPath = stub.path;
  final resolvedPath = resolved.path;
  if (resolvedPath == stubPath ||
      resolvedPath.startsWith('$stubPath${Platform.pathSeparator}')) {
    _die('kelola_pro resolves to the in-repo stub at $resolvedPath');
  }

  stdout.writeln('check_play_billing: kelola_pro -> $resolvedPath');
  stdout.writeln('check_play_billing: ok');
}

void _die(String message) {
  stderr.writeln('check_play_billing: $message');
  exit(1);
}
