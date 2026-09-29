import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android SSH keygen never creates an unauthenticated Keystore key', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/HardwareSignerPlugin.kt',
    ).readAsStringSync();
    expect(kt, isNot(contains('KeyAttempt(strongBox = false, auth = false')));
    expect(kt, isNot(contains('setUserAuthenticationRequired(false)')));
    expect(kt, contains('setUserAuthenticationRequired(true)'));
    expect(kt, contains('"authRequired"'));
  });

  test('enrollment screen surfaces authRequired', () {
    final dart = File(
      'lib/presentation/screens/enrollment_screen.dart',
    ).readAsStringSync();
    expect(dart, contains('enrollment.authRequired'));
    expect(dart, contains('Presence required'));
  });
}
