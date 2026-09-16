import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';
import 'package:kelola/domain/facts/enums.dart';

/// Shared-store property: a newer successful sample must not coexist with
/// a stale unreachable label on another surface.
bool hostsContradictFleet({
  required HostAttention hostsAttention,
  required DateTime? hostsAttentionAt,
  required FleetHostHealth? fleet,
}) {
  if (fleet == null || !fleet.reachable) {
    return false;
  }
  if (hostsAttention != HostAttention.unreachable) {
    return false;
  }
  final hostsAt = hostsAttentionAt;
  if (hostsAt == null) {
    return true; // Fleet healthy, Hosts unreachable with no stamp
  }
  return fleet.fetchedAt.isAfter(hostsAt);
}

void main() {
  test('property: Fleet healthy newer than Hosts unreachable is a contradiction',
      () {
    final fleet = FleetHostHealth(
      hostId: 'h',
      alias: 'east-rock-uat',
      reachable: true,
      load1: 0.16,
      nprocCores: 1,
      memPercent: 20,
      diskRootPercent: 13,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.utc(2026, 9, 7, 12, 52),
      outcome: HostProbeOutcome.healthy,
    );
    expect(
      hostsContradictFleet(
        hostsAttention: HostAttention.unreachable,
        hostsAttentionAt: DateTime.utc(2026, 9, 7, 10, 52),
        fleet: fleet,
      ),
      isTrue,
    );
    expect(
      hostsContradictFleet(
        hostsAttention: HostAttention.healthy,
        hostsAttentionAt: DateTime.utc(2026, 9, 7, 10, 52),
        fleet: fleet,
      ),
      isFalse,
    );
  });

  test('tileSummary never says down', () {
    final timedOut = FleetHostHealth(
      hostId: 'h',
      alias: 'x',
      reachable: false,
      load1: 0,
      diskRootPercent: 0,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.utc(2026, 9, 7),
      fromCache: true,
      outcome: HostProbeOutcome.timedOut,
    );
    final timedOutSummary =
        timedOut.tileSummary(now: DateTime.utc(2026, 9, 7, 0, 5));
    expect(timedOutSummary.toLowerCase(), isNot(contains('down')));
    // Soft timeout is not a hard unreachable claim.
    expect(timedOutSummary, contains('timed out'));
    expect(timedOutSummary.toLowerCase(), isNot(contains('unreachable')));

    final refused = FleetHostHealth(
      hostId: 'h',
      alias: 'x',
      reachable: false,
      load1: 0,
      diskRootPercent: 0,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.utc(2026, 9, 7),
      fromCache: true,
      outcome: HostProbeOutcome.refused,
    );
    final refusedSummary =
        refused.tileSummary(now: DateTime.utc(2026, 9, 7, 0, 5));
    expect(refusedSummary.toLowerCase(), isNot(contains('down')));
    expect(refusedSummary, contains('unreachable'));
    expect(refusedSummary, contains('cache'));
  });
}
