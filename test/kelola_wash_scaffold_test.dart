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

  test('listed screens carry HostsChromeAccent / KelolaWashScaffold wash', () {
    const screens = [
      'lib/presentation/screens/fleet_screen.dart',
      'lib/presentation/screens/llm_settings_screen.dart',
      'lib/presentation/screens/audit_screen.dart',
      'lib/presentation/screens/search_screen.dart',
      'lib/presentation/screens/edit_host_screen.dart',
      'lib/presentation/screens/settings_screen.dart',
      'lib/presentation/screens/hosts_screen.dart',
      'lib/presentation/widgets/kelola_chrome.dart',
    ];
    for (final path in screens) {
      final src = File(path).readAsStringSync();
      expect(
        src.contains('HostsChromeAccent') || src.contains('KelolaWashScaffold'),
        isTrue,
        reason: '$path must use the amber arc wash',
      );
    }
    // Add host + host details go through KelolaPage → KelolaWashScaffold.
    final add = File('lib/presentation/screens/add_host_screen.dart')
        .readAsStringSync();
    expect(add, contains('KelolaPage'));
    final dash = File('lib/presentation/screens/host_dashboard_screen.dart')
        .readAsStringSync();
    expect(dash, contains('KelolaPage'));
  });
}
