import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/audit/probe_audit_policy.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/hosts/poll_backoff.dart';

void main() {
  group('PollBackoff', () {
    test('exponential delay then stop after five consecutive failures', () {
      final b = PollBackoff(base: const Duration(seconds: 5));
      expect(b.stopped, isFalse);
      expect(b.disconnected, isFalse);

      expect(b.failure(), const Duration(seconds: 5));
      expect(b.failure(), const Duration(seconds: 10));
      expect(b.failure(), const Duration(seconds: 20));
      expect(b.failure(), const Duration(seconds: 40));
      expect(b.failure(), isNull);
      expect(b.stopped, isTrue);
      expect(b.disconnected, isTrue);
      expect(b.consecutiveFailures, 5);
    });

    test('success resets consecutive failures', () {
      final b = PollBackoff(base: const Duration(seconds: 5));
      b.failure();
      b.failure();
      b.success();
      expect(b.stopped, isFalse);
      expect(b.disconnected, isFalse);
      expect(b.failure(), const Duration(seconds: 5));
    });
  });

  test('metrics kicker shows disconnected instead of polling', () {
    expect(
      metricsPollKicker(poll: const Duration(seconds: 5), disconnected: false),
      'POLLING · 5S',
    );
    expect(
      metricsPollKicker(poll: const Duration(seconds: 5), disconnected: true),
      'DISCONNECTED',
    );
    expect(
      metricsPollKicker(poll: null, disconnected: false),
      'PAUSED',
    );
  });

  test('metrics and dashboard poll loops use backoff', () {
    final metrics = File('lib/presentation/screens/metrics_screen.dart')
        .readAsStringSync();
    expect(metrics, contains('PollBackoff'));
    expect(metrics, contains('metricsPollKicker'));
  });

  group('ProbeAuditPolicy', () {
    test('one Connection lost record for repeated connection failures', () {
      final policy = ProbeAuditPolicy();
      const hostId = 'h1';
      final errors = [
        const SocketException('Connection refused'),
        SshUnavailableException('dead'),
        const SocketException('Connection reset by peer'),
      ];

      final titles = <String?>[];
      for (var i = 0; i < 36; i++) {
        titles.add(
          policy.titleOnFailure(
            hostId: hostId,
            probeTitle: 'Polled CPU',
            error: errors[i % errors.length],
          ),
        );
      }

      expect(titles.where((t) => t == connectionLostTitle), hasLength(1));
      expect(titles.first, connectionLostTitle);
      expect(titles.skip(1), everyElement(isNull));
      expect(titles.where((t) => t == 'Polled CPU'), isEmpty);
    });

    test('non-connection errors keep the probe title', () {
      final policy = ProbeAuditPolicy();
      expect(
        policy.titleOnFailure(
          hostId: 'h1',
          probeTitle: 'Polled CPU',
          error: StateError('parse'),
        ),
        'Polled CPU',
      );
    });

    test('success clears the lost gate so a later drop is recorded once', () {
      final policy = ProbeAuditPolicy();
      expect(
        policy.titleOnFailure(
          hostId: 'h1',
          probeTitle: 'Polled CPU',
          error: const SocketException('reset'),
        ),
        connectionLostTitle,
      );
      policy.onSuccess('h1');
      expect(
        policy.titleOnFailure(
          hostId: 'h1',
          probeTitle: 'Polled CPU',
          error: const SocketException('reset'),
        ),
        connectionLostTitle,
      );
    });
  });
}
