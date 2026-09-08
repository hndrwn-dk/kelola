import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
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

  group('classifySshBootstrapError', () {
    test('socket timeout maps to connectionFailed', () {
      final failure = classifySshBootstrapError(
        TimeoutException('SSH connect timed out'),
        hostKeyAccepted: false,
        serverAuthMethods: const {},
      );

      expect(failure.mode, PasswordAuthFailureMode.connectionFailed);
      expect(failure.offerRetry, isFalse);
      expect(failure.message.toLowerCase(), contains('connect'));
      expect(failure.message.toLowerCase(), contains('not a password error'));
    });

    test('SocketException maps to connectionFailed even if host key accepted', () {
      final failure = classifySshBootstrapError(
        const SocketException('Connection refused'),
        hostKeyAccepted: true,
        serverAuthMethods: const {'password'},
      );

      expect(failure.mode, PasswordAuthFailureMode.connectionFailed);
      expect(failure.offerRetry, isFalse);
    });

    test('auth abort with no password method is passwordDisabled', () {
      final failure = classifySshBootstrapError(
        SSHAuthAbortError('Connection closed before authentication'),
        hostKeyAccepted: true,
        serverAuthMethods: const {'publickey'},
      );

      expect(failure.mode, PasswordAuthFailureMode.passwordDisabled);
      expect(failure.offerRetry, isFalse);
      expect(
        failure.message.toLowerCase(),
        anyOf(contains('not offered'), contains('disabled'), contains('did not offer')),
      );
    });

    test('auth fail after password offered is rejected with retry', () {
      final failure = classifySshBootstrapError(
        SSHAuthFailError('All authentication methods failed'),
        hostKeyAccepted: true,
        serverAuthMethods: const {'publickey', 'password'},
      );

      expect(failure.mode, PasswordAuthFailureMode.rejected);
      expect(failure.offerRetry, isTrue);
      expect(failure.message.toLowerCase(), contains('password'));
    });

    test('empty methods use message heuristic for password disabled', () {
      final failure = classifySshBootstrapError(
        SSHAuthFailError('password authentication disabled'),
        hostKeyAccepted: true,
        serverAuthMethods: const {},
      );

      expect(failure.mode, PasswordAuthFailureMode.passwordDisabled);
      expect(failure.offerRetry, isFalse);
    });

    test('empty methods default SSHAuthFailError to rejected', () {
      final failure = classifySshBootstrapError(
        SSHAuthFailError('All authentication methods failed'),
        hostKeyAccepted: true,
        serverAuthMethods: const {},
      );

      expect(failure.mode, PasswordAuthFailureMode.rejected);
      expect(failure.offerRetry, isTrue);
    });

    test('host key not accepted is connectionFailed', () {
      final failure = classifySshBootstrapError(
        SSHAuthAbortError('host key rejected', SSHHostkeyError('mismatch')),
        hostKeyAccepted: false,
        serverAuthMethods: const {'password'},
      );

      expect(failure.mode, PasswordAuthFailureMode.connectionFailed);
      expect(failure.offerRetry, isFalse);
    });
  });
}
