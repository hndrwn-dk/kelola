import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_watch.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';

class FleetWatchNotice {
  const FleetWatchNotice({
    required this.hostId,
    required this.alias,
    required this.title,
    required this.body,
  });

  final String hostId;
  final String alias;
  final String title;
  final String body;
}

class FleetWatchRunner {
  FleetWatchRunner({required HostRepository hosts}) : _hosts = hosts;

  final HostRepository _hosts;

  Future<List<FleetWatchNotice>> tick({
    required List<Host> hosts,
    required FleetWatchThresholds thresholds,
    required DateTime now,
    required Future<FleetHostHealth> Function(Host host) probe,
  }) async {
    final notices = <FleetWatchNotice>[];
    for (final host in hosts) {
      FleetHostHealth live;
      try {
        live = await probe(host);
      } catch (_) {
        live = FleetHostHealth(
          hostId: host.id,
          alias: host.alias,
          reachable: false,
          load1: 0,
          failedUnitCount: 0,
          pendingUpdates: 0,
          fetchedAt: now.toUtc(),
          outcome: HostProbeOutcome.unreachable,
        );
      }
      await _hosts.saveFleetCache(live);
      await _hosts.updateAttention(
        id: host.id,
        attention: attentionFromFleetHealth(live),
        failedUnitCount: live.failedUnitCount,
        diskRootPercent: live.diskRootPercent,
        attentionAt: live.fetchedAt,
      );
      final assessment = fleetWatchAssessment(live, thresholds);
      final current = fleetWatchFingerprint(assessment);
      final previous = await _hosts.fleetWatchFingerprint(host.id);
      if (fleetWatchShouldNotify(previous: previous, current: current)) {
        notices.add(
          FleetWatchNotice(
            hostId: host.id,
            alias: host.alias,
            title: host.alias,
            body: fleetWatchNoticeBody(assessment),
          ),
        );
      }
      await _hosts.setFleetWatchFingerprint(host.id, current);
    }
    await _hosts.setFleetWatchLastTickAt(now.toUtc());
    return notices;
  }
}
