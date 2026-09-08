import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/enrollment/password_auth_failure.dart';

void main() {
  group('classifyPasswordAuthFailure', () {
    test('host key not verified is connectionFailed without credential retry', () {
      final failure = classifyPasswordAuthFailure(
        error: StateError('handshake aborted'),
        hostKeyVerified: false,
        passwordMethodOffered: false,
      );

      expect(failure.mode, PasswordAuthFailureMode.connectionFailed);
      expect(failure.offerRetry, isFalse);
      expect(failure.message.toLowerCase(), contains('connect'));
      expect(failure.message.toLowerCase(), contains('not a password error'));
    });

    test('host key ok but password not offered is passwordDisabled', () {
      final failure = classifyPasswordAuthFailure(
        error: StateError('no password method'),
        hostKeyVerified: true,
        passwordMethodOffered: false,
      );

      expect(failure.mode, PasswordAuthFailureMode.passwordDisabled);
      expect(failure.offerRetry, isFalse);
      expect(failure.message.toLowerCase(), contains('password'));
      expect(
        failure.message.toLowerCase(),
        anyOf(contains('not offered'), contains('disabled'), contains('did not offer')),
      );
    });

    test('host key ok and password offered but rejected offers retry', () {
      final failure = classifyPasswordAuthFailure(
        error: StateError('auth failed'),
        hostKeyVerified: true,
        passwordMethodOffered: true,
      );

      expect(failure.mode, PasswordAuthFailureMode.rejected);
      expect(failure.offerRetry, isTrue);
      expect(failure.message.toLowerCase(), contains('password'));
      expect(
        failure.message.toLowerCase(),
        anyOf(contains('authentication'), contains('credential')),
      );
    });

    test('three modes produce distinct messages', () {
      final connection = classifyPasswordAuthFailure(
        error: StateError('socket'),
        hostKeyVerified: false,
        passwordMethodOffered: true,
      );
      final disabled = classifyPasswordAuthFailure(
        error: StateError('methods'),
        hostKeyVerified: true,
        passwordMethodOffered: false,
      );
      final rejected = classifyPasswordAuthFailure(
        error: StateError('bad password'),
        hostKeyVerified: true,
        passwordMethodOffered: true,
      );

      expect(connection.message, isNot(disabled.message));
      expect(connection.message, isNot(rejected.message));
      expect(disabled.message, isNot(rejected.message));
    });
  });
}
