import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final root = Directory.current.path;

  test('only entitlement.dart in lib imports kelola_pro', () {
    final hits = _filesContaining(
      p.join(root, 'lib'),
      'package:kelola_pro',
    );
    expect(hits, ['lib/domain/entitlement/entitlement.dart']);
  });

  test('lib does not import a billing package', () {
    const banned = [
      'package:in_app_purchase',
      'package:purchases_flutter',
      'package:flutter_inapp_purchase',
    ];
    final hits = <String>[];
    for (final file in _dartFiles(p.join(root, 'lib'))) {
      final src = file.readAsStringSync();
      for (final token in banned) {
        if (src.contains(token)) {
          hits.add('${_rel(file, root)} $token');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('tunnels, ssh, and fleet domain do not import entitlement', () {
    final seeds = [
      p.join(root, 'lib', 'domain', 'tunnels'),
      p.join(root, 'lib', 'data', 'ssh'),
      p.join(root, 'lib', 'domain', 'fleet'),
    ];
    final forbidden = {
      p.normalize(
        p.join(root, 'lib', 'domain', 'entitlement', 'entitlement.dart'),
      ),
    };
    final hits = <String>[];
    for (final seed in seeds) {
      for (final file in _dartFiles(seed)) {
        if (_reaches(file.path, root, forbidden, alsoContains: 'package:kelola_pro')) {
          hits.add(_rel(file, root));
        }
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('kelola_pro does not import the app', () {
    final hits = <String>[];
    for (final file in _dartFiles(p.join(root, 'packages', 'kelola_pro'))) {
      final src = file.readAsStringSync();
      if (src.contains('package:kelola/') || src.contains("import '../lib")) {
        hits.add(_rel(file, root));
      }
    }
    expect(hits, isEmpty);
  });

  test('createEntitlement is called from exactly one place in lib', () {
    expect(
      _occurrenceFiles(p.join(root, 'lib'), 'createEntitlement('),
      ['lib/domain/entitlement/entitlement.dart x1'],
    );
  });

  test('isUnlocked(ProFeature.tunnels) has exactly one production read', () {
    expect(
      _occurrenceFiles(
        p.join(root, 'lib'),
        'isUnlocked(ProFeature.tunnels)',
      ),
      ['lib/presentation/screens/host_dashboard_screen.dart x1'],
    );
  });

  test('TunnelManager does not call isUnlocked', () {
    final src = File(
      p.join(root, 'lib', 'data', 'ssh', 'tunnel_manager.dart'),
    ).readAsStringSync();
    expect(src.contains('isUnlocked'), isFalse);
  });
}

List<String> _occurrenceFiles(String dir, String token) {
  final root = Directory.current.path;
  final hits = <String>[];
  for (final file in _dartFiles(dir)) {
    final count = token.allMatches(file.readAsStringSync()).length;
    if (count == 0) {
      continue;
    }
    hits.add('${_rel(file, root)} x$count');
  }
  hits.sort();
  return hits;
}

List<String> _filesContaining(String dir, String token) {
  final root = Directory.current.path;
  final hits = <String>[];
  for (final file in _dartFiles(dir)) {
    if (file.readAsStringSync().contains(token)) {
      hits.add(_rel(file, root));
    }
  }
  hits.sort();
  return hits;
}

Iterable<File> _dartFiles(String dir) sync* {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    return;
  }
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity;
    }
  }
}

String _rel(File file, String root) =>
    p.relative(file.path, from: root).replaceAll('\\', '/');

bool _reaches(
  String startFile,
  String root,
  Set<String> forbidden, {
  required String alsoContains,
}) {
  final visited = <String>{};
  final queue = <String>[p.normalize(startFile)];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    if (!visited.add(current)) {
      continue;
    }
    if (forbidden.contains(current)) {
      return true;
    }
    final file = File(current);
    if (!file.existsSync()) {
      continue;
    }
    final src = file.readAsStringSync();
    if (src.contains(alsoContains)) {
      return true;
    }
    for (final next in _importsOf(file, root)) {
      if (!visited.contains(next)) {
        queue.add(next);
      }
    }
  }
  return false;
}

Iterable<String> _importsOf(File file, String root) sync* {
  final dir = p.dirname(file.path);
  for (final raw in file.readAsStringSync().split('\n')) {
    final line = raw.trim();
    final match = RegExp(r"""^import\s+['"]([^'"]+)['"]""").firstMatch(line);
    if (match == null) {
      continue;
    }
    final uri = match.group(1)!;
    if (uri.startsWith('dart:') || uri.startsWith('package:') && !uri.startsWith('package:kelola/')) {
      continue;
    }
    if (uri.startsWith('package:kelola/')) {
      yield p.normalize(p.join(root, 'lib', uri.substring('package:kelola/'.length)));
      continue;
    }
    yield p.normalize(p.join(dir, uri));
  }
}
