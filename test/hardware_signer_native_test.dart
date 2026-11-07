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

  group('Android shows one biometric prompt at a time', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/HardwareSignerPlugin.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    String body(String signature) {
      final start = kt.indexOf(signature);
      expect(start, greaterThan(-1), reason: signature);
      return kt.substring(start, kt.indexOf('\n    }\n', start));
    }

    const prompts = [
      'private fun confirmPresence(',
      'private fun unlockThenSign(',
      'private fun signWithCryptoObject(',
    ];

    test('confirmPresence fails busy before it builds a prompt', () {
      final fn = body('private fun confirmPresence(');
      final busy = fn.indexOf('"busy"');
      expect(busy, greaterThan(-1));
      expect(fn.indexOf('promptResult != null'), lessThan(busy));
      expect(busy, lessThan(fn.indexOf('BiometricPrompt(')));
    });

    test('every prompt is claimed before it is built', () {
      for (final name in prompts) {
        final fn = body(name);
        final claim = fn.indexOf('beginPrompt(act, result)');
        expect(claim, greaterThan(-1), reason: name);
        expect(claim, lessThan(fn.indexOf('BiometricPrompt(')), reason: name);
      }
    });

    test('every way out of a prompt releases it', () {
      for (final name in prompts) {
        // Success, error, and a failed start.
        expect(
          'endPrompt(result)'.allMatches(body(name)),
          hasLength(3),
          reason: name,
        );
      }
    });

    test('no prompt starts once state is saved', () {
      final fn = body('private fun beginPrompt(');
      expect(fn, contains('isStateSaved'));
      expect(
        fn.indexOf('isStateSaved'),
        lessThan(fn.indexOf('promptResult = result')),
      );
    });

    test('a closed activity releases its prompt', () {
      final fn = body('override fun onDetachedFromActivity() {');
      expect(fn, contains('promptResult = null'));
      expect(fn, contains('waiting?.error('));
    });
  });

  test('enrollment screen surfaces authRequired', () {
    final dart = File(
      'lib/presentation/screens/enrollment_screen.dart',
    ).readAsStringSync();
    expect(dart, contains('enrollment.authRequired'));
    expect(dart, contains('Presence required'));
  });
}
