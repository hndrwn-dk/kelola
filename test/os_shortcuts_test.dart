import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/shortcuts/os_shortcuts.dart';

void main() {
  test('omits shortcuts until lastHostId is set', () {
    expect(
      buildOsShortcuts(lastHostId: null, lastHostHasTunnelTarget: true),
      isEmpty,
    );
  });

  test('two shortcuts without tunnel targets, three with', () {
    final two = buildOsShortcuts(
      lastHostId: 'abc',
      lastHostHasTunnelTarget: false,
    );
    expect(two.map((s) => s.id).toList(), ['last_host', 'incident']);
    expect(two[0].uri, 'kelola://host/abc');
    expect(two[0].label, 'Last host');
    expect(two[1].uri, 'kelola://host/abc/incident');
    expect(two[1].label, 'Incident');

    final three = buildOsShortcuts(
      lastHostId: 'abc',
      lastHostHasTunnelTarget: true,
    );
    expect(
      three.map((s) => s.id).toList(),
      ['last_host', 'incident', 'last_tunnel'],
    );
    expect(three[2].uri, 'kelola://host/abc/tunnel');
    expect(three[2].label, 'Last tunnel');
  });

  test('native plugin publishes VIEW intents to kelola URIs', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/ShortcutsPlugin.kt',
    ).readAsStringSync();
    expect(kt, contains('ShortcutManager'));
    expect(kt, contains('ACTION_VIEW'));
    expect(kt, contains('com.tursinalabs.kelola/shortcuts'));
    expect(kt, contains('MainActivity'));
  });
}
