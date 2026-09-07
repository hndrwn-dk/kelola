import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';

void main() {
  test('only connection-failure outcomes are unreachable-class', () {
    for (final o in HostProbeOutcome.values) {
      final isFail = isConnectionFailureOutcome(o);
      final label = hostProbeStateLabel(o);
      if (isFail) {
        expect(label, 'unreachable');
      } else {
        expect(label.toLowerCase(), isNot(contains('down')));
        expect(label, isNot('unreachable'));
      }
    }
  });

  test('state label never contains down', () {
    for (final o in HostProbeOutcome.values) {
      expect(hostProbeStateLabel(o).toLowerCase(), isNot(contains('down')));
      expect(
        fleetUnreachableMessage(
          outcome: o,
          hasCache: true,
          fetchedAt: DateTime.utc(2026, 9, 7),
          now: DateTime.utc(2026, 9, 7, 0, 5),
        ).toLowerCase(),
        isNot(contains('down')),
      );
    }
  });

  test('exhaustive switch covers every outcome (no default)', () {
    // Compiles only if every value is handled — mirrors production switches.
    String label(HostProbeOutcome o) => switch (o) {
          HostProbeOutcome.pending => 'p',
          HostProbeOutcome.awaitingVerification => 'v',
          HostProbeOutcome.awaitingAuth => 'a',
          HostProbeOutcome.unchecked => 'u',
          HostProbeOutcome.timedOut => 't',
          HostProbeOutcome.refused => 'r',
          HostProbeOutcome.unreachable => 'x',
          HostProbeOutcome.healthy => 'h',
        };
    expect(
      HostProbeOutcome.values.map(label).toSet(),
      {'p', 'v', 'a', 'u', 't', 'r', 'x', 'h'},
    );
  });
}
