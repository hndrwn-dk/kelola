import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String manifest;

  setUpAll(() {
    manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  });

  Set<String> usesPermissions() {
    final re = RegExp(r'android:name="(android\.permission\.[A-Z0-9_]+)"');
    return re.allMatches(manifest).map((m) => m.group(1)!).toSet();
  }

  test('manifest permissions are prior set plus FGS + POST_NOTIFICATIONS only', () {
    const prior = {
      'android.permission.INTERNET',
      'android.permission.USE_BIOMETRIC',
    };
    const added = {
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
      'android.permission.POST_NOTIFICATIONS',
    };
    expect(usesPermissions(), prior.union(added));
  });

  test('manifest must not declare connected-device prerequisite permissions', () {
    expect(manifest.contains('CHANGE_NETWORK_STATE'), isFalse);
    expect(manifest.contains('CHANGE_WIFI_STATE'), isFalse);
    expect(manifest.contains('BLUETOOTH'), isFalse);
    expect(manifest.contains('android.hardware.usb'), isFalse);
    expect(manifest.contains('android.permission.NFC'), isFalse);
    expect(manifest.contains('android.hardware.nfc'), isFalse);
  });

  test('TunnelForegroundService is specialUse and not exported', () {
    expect(manifest, contains('android:name=".TunnelForegroundService"'));
    expect(manifest, contains('android:foregroundServiceType="specialUse"'));
    expect(manifest, contains('android:exported="false"'));
    expect(
      manifest,
      contains('android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE'),
    );
    expect(
      manifest,
      contains('SSH local port forwarding to user-managed hosts'),
    );
  });
}
