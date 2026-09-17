import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
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
