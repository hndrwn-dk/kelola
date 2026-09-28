import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('KelolaWashScaffold applies SafeArea once and strips body top padding', () {
    final src = File('lib/design/kelola_components.dart').readAsStringSync();
    final start = src.indexOf('class KelolaWashScaffold');
    final end = src.indexOf('class HostsUtilityRail');
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start));
    final block = src.substring(start, end);
    expect(block, contains('SafeArea('));
    expect(block, contains('removeTop: true'));
    expect(block, isNot(contains('extendBodyBehindAppBar: true')));
    expect(block.split('SafeArea(').length - 1, 1);
  });

  test('full-page screens use KelolaWashScaffold or KelolaPage, not a raw Scaffold',
      () {
    final dir = Directory('lib/presentation/screens');
    final skip = {
      'boot_gate.dart',
    };
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.contains('sheet'))
        .where((f) => !skip.contains(f.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);
    for (final file in files) {
      final src = file.readAsStringSync();
      final name = file.uri.pathSegments.last;
      expect(
        src.contains('KelolaWashScaffold') || src.contains('KelolaPage'),
        isTrue,
        reason: '$name must paint HostsChromeAccent via wash or KelolaPage',
      );
      expect(
        src.contains('return Scaffold('),
        isFalse,
        reason: '$name still returns a raw Scaffold',
      );
    }
    final chrome =
        File('lib/presentation/widgets/kelola_chrome.dart').readAsStringSync();
    expect(chrome, contains('KelolaWashScaffold'));
  });
}
