import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fleet_screen does not import or reference RiskLevel', () {
    final src = File('lib/presentation/screens/fleet_screen.dart').readAsStringSync();
    expect(src.contains('risk_level'), isFalse);
    expect(src.contains('RiskLevel'), isFalse);
    expect(src.contains('tileRiskLevel'), isFalse);
  });

  test('FleetHostTile API is health-status based, not RiskLevel', () {
    final src = File('lib/design/kelola_components.dart').readAsStringSync();
    final start = src.indexOf('class FleetHostTile');
    expect(start, greaterThanOrEqualTo(0));
    final end = src.indexOf('\nclass ', start + 1);
    final body = src.substring(start, end > start ? end : src.length);
    expect(body.contains('RiskLevel'), isFalse);
    expect(body.contains('HealthStatus'), isTrue);
  });

  test('fleet_screen source never references WebLensProbe or ServiceDetectProbe',
      () {
    final src = File('lib/presentation/screens/fleet_screen.dart').readAsStringSync();
    expect(src.contains('WebLensProbe'), isFalse);
    expect(src.contains('ServiceDetectProbe'), isFalse);
    expect(src.contains('ConfigTestedReloadProbe'), isFalse);
    expect(src.contains('web_lens_probe'), isFalse);
    expect(src.contains('service_detect_probe'), isFalse);
    expect(src.contains('config_tested_reload_probe'), isFalse);
    // The service pills read the cache only.
    expect(src.contains('serviceLensStoreProvider'), isTrue);
  });
}
