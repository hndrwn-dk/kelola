import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/fleet/fleet_watch_bridge.dart';
import 'package:kelola/data/fleet/fleet_watch_runner.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/widget/home_widget_bridge.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_watch.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';

class FleetWatchController {
  FleetWatchController({
    required this.hosts,
    required this.pool,
    required this.bridge,
    required this.widgetBridge,
    required this.entitlement,
    required this.selectedHostIds,
  });

  final HostRepository hosts;
  final SshSessionPool pool;
  final FleetWatchBridge bridge;
  final HomeWidgetBridge widgetBridge;
  final Entitlement entitlement;
  final Future<Set<String>?> Function() selectedHostIds;

  Future<void> setEnabled(bool enabled) async {
    if (!entitlement.isUnlocked(ProFeature.fleetWatch)) {
      return;
    }
    await hosts.setFleetWatchEnabled(enabled);
    if (enabled) {
      await bridge.requestPostNotifications();
      await bridge.schedule();
      await maybeTick(force: true);
    } else {
      await bridge.cancel();
    }
  }

  Future<void> maybeTick({
    bool force = false,
    DateTime? now,
  }) async {
    if (!entitlement.isUnlocked(ProFeature.fleetWatch)) {
      return;
    }
    if (!await hosts.fleetWatchEnabled()) {
      return;
    }
    final clock = now ?? DateTime.now().toUtc();
    if (!force &&
        !fleetWatchIsDue(
          lastTickUtc: await hosts.fleetWatchLastTickAt(),
          now: clock,
        )) {
      return;
    }
    final all = await hosts.list();
    final plan = planFleetProbes(
      hostIds: [for (final host in all) host.id],
      selectedHostIds: await selectedHostIds(),
      fleetUnlimited: entitlement.isUnlocked(ProFeature.fleetUnlimited),
    );
    final toProbe = [
      for (final host in all)
        if (plan.isMonitored(host.id)) host,
    ];
    final runner = FleetWatchRunner(hosts: hosts);
    final cache = await hosts.loadFleetCacheByHost();
    final notices = await runner.tick(
      hosts: toProbe,
      thresholds: await hosts.fleetWatchThresholds(),
      now: clock,
      probe: (host) => _probe(host, cache[host.id]),
    );
    final enabled = await hosts.widgetEnabled();
    await widgetBridge.write(
      pickWorstHostSnapshot(await hosts.list(), enabled: enabled, now: clock),
    );
    for (final notice in notices) {
      await bridge.notify(notice);
    }
  }

  Future<FleetHostHealth> _probe(Host host, FleetHostHealth? cached) async {
    const scope = ProbeScope.fleet;
    final facts = await hosts.facts(host.id) ?? HostFacts.undiscovered;
    final probe = FleetHealthProbe(
      hostId: host.id,
      alias: host.alias,
      pkg: facts.pkg,
    );
    assertFleetReadOnly(probe, scope: scope);
    final health = await pool.execute(
      host,
      probe,
      facts: facts,
      scope: scope,
    );
    return FleetHostHealth(
      hostId: host.id,
      alias: host.alias,
      reachable: health.reachable,
      load1: health.load1,
      nprocCores: health.nprocCores,
      memPercent: health.memPercent,
      diskRootPercent: health.diskRootPercent,
      highDiskMounts: health.highDiskMounts,
      failedUnitCount: health.failedUnitCount,
      pendingUpdates: cached?.pendingUpdates ?? health.pendingUpdates,
      securityUpdates: cached?.securityUpdates ?? health.securityUpdates,
      containersDown: health.containersDown,
      containersUnhealthy: health.containersUnhealthy,
      uptime: health.uptime,
      rebootRequired: health.rebootRequired,
      fetchedAt: DateTime.now().toUtc(),
    );
  }
}
