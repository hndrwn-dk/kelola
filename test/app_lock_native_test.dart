import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppLockPlugin is a plain biometric gate, not a crypto signer', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/AppLockPlugin.kt',
    ).readAsStringSync();
    expect(kt, contains('BIOMETRIC_STRONG'));
    expect(kt, contains('DEVICE_CREDENTIAL'));
    expect(kt, contains('FLAG_SECURE'));
    expect(kt, contains('canAuthenticate'));
    expect(kt, contains('authenticate'));
    expect(kt, contains('setSecure'));
    expect(kt, isNot(contains('CryptoObject')));
    expect(kt, isNot(contains('setNegativeButtonText')));

    final main = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/MainActivity.kt',
    ).readAsStringSync();
    expect(main, contains('AppLockPlugin()'));

    final swift = File('ios/Runner/AppLockPlugin.swift').readAsStringSync();
    expect(swift, contains('deviceOwnerAuthentication'));
    expect(swift, contains('canAuthenticate'));
    expect(swift, contains('authenticate'));
  });
}
