import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:path/path.dart' as p;

/// Transitive import graph: tunnels domain and SSH data must not reach entitlement.
void main() {
  final root = Directory.current.path;
  final seeds = [
    p.join(root, 'lib', 'domain', 'tunnels'),
    p.join(root, 'lib', 'data', 'ssh'),
  ];
  final forbiddenEntitlement = p.normalize(
    p.join(root, 'lib', 'domain', 'entitlement', 'entitlement.dart'),
  );

  test('tunnel and SSH module seeds exist', () {
    for (final dir in seeds) {
      expect(
        Directory(dir).existsSync(),
        isTrue,
        reason: 'expected $dir for M5',
      );
    }
  });

  test('OpenEntitlement unlocks tunnels by default', () {
    expect(const OpenEntitlement().tunnelsUnlocked, isTrue);
  });

  test('transitive imports never reach entitlement.dart', () {
    final forbidden = {forbiddenEntitlement};
    final hits = <String>[];
    for (final seed in seeds) {
      final dir = Directory(seed);
      if (!dir.existsSync()) {
        fail('missing $seed');
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = _reachForbidden(entity.path, root, forbidden);
        if (path != null) {
          hits.add('${p.relative(entity.path, from: root)} → $path');
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}

String? _reachForbidden(
  String startFile,
  String root,
  Set<String> forbidden,
) {
  final visited = <String>{};
  final queue = <String>[p.normalize(startFile)];
  final parent = <String, String>{};

  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!visited.add(current)) {
      continue;
    }
    if (forbidden.contains(current)) {
      return _chain(current, parent, root);
    }
    final file = File(current);
    if (!file.existsSync()) {
      continue;
    }
    for (final next in _importsOf(file, root)) {
      if (!visited.contains(next)) {
        parent[next] = current;
        queue.add(next);
      }
    }
  }
  return null;
}

String _chain(String leaf, Map<String, String> parent, String root) {
  final parts = <String>[p.relative(leaf, from: root)];
  var cur = leaf;
  while (parent.containsKey(cur)) {
    cur = parent[cur]!;
    parts.add(p.relative(cur, from: root));
  }
  return parts.reversed.join(' → ');
}

Iterable<String> _importsOf(File file, String root) sync* {
  final dir = p.dirname(file.path);
  final lines = file.readAsStringSync().split('\n');
  for (final raw in lines) {
    final line = raw.trim();
    final m = RegExp(
      r"""^import\s+['"]([^'"]+)['"]""",
    ).firstMatch(line);
    if (m == null) {
      continue;
    }
    final uri = m.group(1)!;
    if (uri.startsWith('dart:')) {
      continue;
    }
    if (uri.startsWith('package:kelola/')) {
      final rel = uri.substring('package:kelola/'.length);
      yield p.normalize(p.join(root, 'lib', rel));
      continue;
    }
    if (uri.startsWith('package:')) {
      continue;
    }
    yield p.normalize(p.join(dir, uri));
  }
}
