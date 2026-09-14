import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';

void main() {
  const hosts = ['a', 'b', 'c', 'd', 'e'];

  test('unlocked probes every host and ignores a stored selection of two', () {
    final plan = planFleetProbes(
      hostIds: hosts,
      selectedHostIds: {'a', 'b'},
      fleetUnlimited: true,
    );

    expect(plan.probedHostIds, hosts.toSet());
    expect(plan.addHostLocked, isFalse);
    expect(plan.showProbeToggles, isFalse);
    expect(plan.showChoosePrompt, isFalse);
    expect(plan.selectingAnotherIsLocked('c'), isFalse);
    for (final id in hosts) {
      expect(plan.isMonitored(id), isTrue, reason: id);
    }
  });

  test('locked with three or fewer hosts probes all of them', () {
    final plan = planFleetProbes(
      hostIds: const ['a', 'b', 'c'],
      selectedHostIds: const {},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, {'a', 'b', 'c'});
    expect(plan.addHostLocked, isTrue);
    expect(plan.showProbeToggles, isFalse);
    expect(plan.showChoosePrompt, isFalse);
    expect(plan.isMonitored('a'), isTrue);
  });

  test('locked under the cap does not lock adding another host', () {
    final plan = planFleetProbes(
      hostIds: const ['a', 'b'],
      selectedHostIds: const {},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, {'a', 'b'});
    expect(plan.addHostLocked, isFalse);
    expect(plan.showProbeToggles, isFalse);
    expect(plan.showChoosePrompt, isFalse);
  });

  test('locked over the cap and never chosen probes nobody and prompts', () {
    final plan = planFleetProbes(
      hostIds: hosts,
      selectedHostIds: null,
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, isEmpty);
    expect(plan.addHostLocked, isTrue);
    expect(plan.showProbeToggles, isTrue);
    expect(plan.showChoosePrompt, isTrue);
    expect(plan.selectingAnotherIsLocked('a'), isFalse);
    for (final id in hosts) {
      expect(plan.isMonitored(id), isFalse, reason: id);
    }
  });

  test('locked over the cap with an explicit empty choice probes nobody and does not prompt', () {
    final plan = planFleetProbes(
      hostIds: hosts,
      selectedHostIds: const {},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, isEmpty);
    expect(plan.addHostLocked, isTrue);
    expect(plan.showProbeToggles, isTrue);
    expect(plan.showChoosePrompt, isFalse);
    expect(plan.selectingAnotherIsLocked('a'), isFalse);
  });

  test('locked over the cap probes only the selected hosts', () {
    final plan = planFleetProbes(
      hostIds: hosts,
      selectedHostIds: {'b', 'd', 'missing'},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, {'b', 'd'});
    expect(plan.isMonitored('a'), isFalse);
    expect(plan.isMonitored('b'), isTrue);
    expect(plan.addHostLocked, isTrue);
    expect(plan.showProbeToggles, isTrue);
    expect(plan.showChoosePrompt, isFalse);
    expect(plan.selectingAnotherIsLocked('a'), isFalse);
    expect(plan.selectingAnotherIsLocked('e'), isFalse);
  });

  test('selecting a fourth probe is locked and does not depend on write-then-rollback', () {
    final plan = planFleetProbes(
      hostIds: hosts,
      selectedHostIds: {'a', 'b', 'c'},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, {'a', 'b', 'c'});
    expect(plan.selectingAnotherIsLocked('d'), isTrue);
    expect(plan.selectingAnotherIsLocked('a'), isFalse);
  });

  test('unknown selected ids never become probed hosts', () {
    final plan = planFleetProbes(
      hostIds: const ['a'],
      selectedHostIds: {'gone', 'a'},
      fleetUnlimited: false,
    );

    expect(plan.probedHostIds, {'a'});
  });
}
