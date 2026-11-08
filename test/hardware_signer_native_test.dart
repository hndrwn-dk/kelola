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

  group('Android queues a signature behind an open prompt', () {
    final kt = File(
      'android/app/src/main/kotlin/com/tursinalabs/kelola/HardwareSignerPlugin.kt',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('a sign that needs a prompt waits instead of starting one', () {
      final sign = kt.substring(kt.indexOf('private fun sign('));
      final check = sign.indexOf('if (promptResult != null)');
      final wait = sign.indexOf('waitingSigns.addLast');
      final start = sign.indexOf('unlockThenSign(act, privateKey, data, result)');
      expect(check, greaterThan(0));
      expect(wait, greaterThan(check));
      expect(start, greaterThan(wait));
    });

    test('a key the prompt opened still signs without waiting', () {
      final sign = kt.substring(kt.indexOf('private fun sign('));
      expect(
        sign.indexOf('result.success(signWith(privateKey, data))'),
        lessThan(sign.indexOf('waitingSigns.addLast')),
      );
    });

    test('ending a prompt runs the next, after it has gone', () {
      final end = kt.substring(kt.indexOf('private fun endPrompt('));
      expect(end, contains('mainHandler.postDelayed({ runNextSign() }'));
      final next = kt.substring(kt.indexOf('private fun runNextSign('));
      expect(next, contains('while (promptResult == null)'));
      expect(next, contains('next.result.error("sign_failed"'));
    });

    test('the gap between prompts is declared once', () {
      expect('const val PROMPT_GAP_MS'.allMatches(kt).length, 1);
    });

    test('confirmations still refuse rather than wait', () {
      final confirm = kt.substring(kt.indexOf('private fun confirmPresence('));
      expect(confirm, contains('"busy"'));
      expect(
        confirm.substring(0, confirm.indexOf('private fun sign(')),
        isNot(contains('waitingSigns')),
      );
    });

    test('nothing waiting is left unanswered when the activity closes', () {
      final detach = kt.substring(kt.indexOf('override fun onDetachedFromActivity()'));
      expect(
        detach.substring(0, detach.indexOf('onReattachedToActivity')),
        contains('waitingSigns.removeFirst().result.error('),
      );
    });
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
