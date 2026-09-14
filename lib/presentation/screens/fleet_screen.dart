import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/fleet_host_sheet.dart';
import 'package:kelola/providers.dart';

HealthStatus fleetTileHealthStatus(FleetHostHealth h) {
  return switch (assessFleetHost(h).tileHealth) {
    FleetTileHealth.healthy => HealthStatus.healthy,
    FleetTileHealth.warning => HealthStatus.warning,
    FleetTileHealth.failed => HealthStatus.failed,
    FleetTileHealth.unknown => HealthStatus.unknown,
  };
}

class FleetScreen extends ConsumerStatefulWidget {
  const FleetScreen({super.key});

  @override
  ConsumerState<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends ConsumerState<FleetScreen> {
  final Map<String, FleetHostHealth> _byId = {};
  final Set<String> _loading = {};
  List<String> _allTags = const [];
  String? _tagFilter;
  bool _refreshing = false;
  var _probesStarted = false;
  ProviderSubscription<AsyncValue<Set<String>?>>? _selectionSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _selectionSub?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final repo = ref.read(hostRepositoryProvider);
    final cache = await repo.loadFleetCacheByHost();
    final tags = await repo.listAllTags();
    if (!mounted) {
      return;
    }
    setState(() {
      _byId
        ..clear()
        ..addAll(cache);
      _allTags = tags;
    });
    // Do not await the selection future here. path_provider's channel can
    // outlive the first frame, and awaiting it from initState deadlocks
    // widget tests. Refresh once the selection value or error is in.
    _selectionSub = ref.listenManual(fleetProbeSelectionProvider, (previous, next) {
      if (_probesStarted) {
        return;
      }
      if (!next.hasValue && !next.hasError) {
        return;
      }
      _probesStarted = true;
      _refresh();
    });
    final current = ref.read(fleetProbeSelectionProvider);
    if (!_probesStarted && (current.hasValue || current.hasError)) {
      _probesStarted = true;
      await _refresh();
    }
  }

  FleetProbePlan _planFor(List<Host> hosts) {
    final selected = ref.read(fleetProbeSelectionProvider).valueOrNull;
    return planFleetProbes(
      hostIds: [for (final host in hosts) host.id],
      selectedHostIds: selected,
      fleetUnlimited: ref
          .read(entitlementProvider)
          .isUnlocked(ProFeature.fleetUnlimited),
    );
  }

  void _applyHealth(FleetHostHealth health) {
    setState(() => _byId[health.hostId] = health);
  }

  Future<void> _refresh() async {
    final hosts = await ref.read(hostsProvider.future);
    if (!mounted) {
      return;
    }
    if (hosts.isEmpty) {
      setState(() {
        _refreshing = false;
        _loading.clear();
      });
      return;
    }
    final plan = _planFor(hosts);
    final toProbe = [
      for (final host in hosts)
        if (plan.probedHostIds.contains(host.id)) host,
    ];
    setState(() {
      _refreshing = toProbe.isNotEmpty;
      _loading
        ..clear()
        ..addAll(toProbe.map((h) => h.id));
      _allTags = {
        for (final h in hosts) ...h.tags,
      }.toList()
        ..sort();
    });
    if (toProbe.isEmpty) {
      return;
    }

    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
    } catch (_) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _loading.clear();
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }

    await runPooled(
      toProbe,
      concurrency: 5,
      timeout: const Duration(seconds: 10),
      fn: (host) async {
        const scope = ProbeScope.fleet;
        final probe = FleetHealthProbe(hostId: host.id, alias: host.alias);
        assertFleetReadOnly(probe, scope: scope);
        final facts = await ref.read(hostRepositoryProvider).facts(host.id) ??
            HostFacts.undiscovered;
        final health = await runHostProbe(
          ref: ref,
          context: context,
          host: host,
          probe: probe,
          facts: facts,
          scope: scope,
        );
        final live = FleetHostHealth(
          hostId: host.id,
          alias: host.alias,
          reachable: true,
          load1: health.load1,
          nprocCores: health.nprocCores,
          memPercent: health.memPercent,
          diskRootPercent: health.diskRootPercent,
          highDiskMounts: health.highDiskMounts,
          failedUnitCount: health.failedUnitCount,
          pendingUpdates: health.pendingUpdates,
          securityUpdates: health.securityUpdates,
          containersDown: health.containersDown,
          containersUnhealthy: health.containersUnhealthy,
          uptime: health.uptime,
          rebootRequired: health.rebootRequired,
          fetchedAt: DateTime.now().toUtc(),
          outcome: HostProbeOutcome.healthy,
        );
        await ref.read(hostRepositoryProvider).saveFleetCache(live);
        await ref.read(hostRepositoryProvider).updateAttention(
              id: host.id,
              attention: attentionFromFleetHealth(live),
              failedUnitCount: live.failedUnitCount,
              diskRootPercent: live.diskRootPercent,
              attentionAt: live.fetchedAt,
              lastSeenAt: live.fetchedAt,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _byId[host.id] = live;
          _loading.remove(host.id);
        });
      },
      onItemDone: (host, error) async {
        if (!mounted || error == null) {
          return;
        }
        final cached = _byId[host.id];
        final outcome = classifyProbeFailure(error);
        final unreachable = FleetHostHealth(
          hostId: host.id,
          alias: host.alias,
          reachable: false,
          load1: cached?.load1 ?? 0,
          nprocCores: cached?.nprocCores,
          memPercent: cached?.memPercent ?? 0,
          diskRootPercent: cached?.diskRootPercent ?? 0,
          highDiskMounts: cached?.highDiskMounts ?? const [],
          failedUnitCount: cached?.failedUnitCount ?? 0,
          pendingUpdates: cached?.pendingUpdates ?? 0,
          securityUpdates: cached?.securityUpdates ?? 0,
          containersDown: cached?.containersDown ?? 0,
          containersUnhealthy: cached?.containersUnhealthy ?? 0,
          uptime: cached?.uptime ?? Duration.zero,
          rebootRequired: cached?.rebootRequired ?? false,
          fetchedAt: cached?.fetchedAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          fromCache: cached != null,
          outcome: outcome,
        );
        if (cached != null) {
          await ref.read(hostRepositoryProvider).saveFleetCache(unreachable);
        }
        if (isConnectionFailureOutcome(outcome)) {
          await ref.read(hostRepositoryProvider).updateAttention(
                id: host.id,
                attention: HostAttention.unreachable,
                attentionAt: DateTime.now().toUtc(),
              );
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _byId[host.id] = unreachable;
          _loading.remove(host.id);
        });
      },
    );

    if (mounted) {
      setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    ref.watch(entitlementRevisionProvider);
    final hostsAsync = ref.watch(hostsProvider);
    final hosts = hostsAsync.valueOrNull ?? const <Host>[];
    final selected = ref.watch(fleetProbeSelectionProvider).valueOrNull;
    final plan = planFleetProbes(
      hostIds: [for (final host in hosts) host.id],
      selectedHostIds: selected,
      fleetUnlimited:
          ref.watch(entitlementProvider).isUnlocked(ProFeature.fleetUnlimited),
    );
    final tagsByHost = {for (final h in hosts) h.id: h.tags};

    final rows = <FleetHostHealth>[
      for (final h in hosts)
        if (!plan.isMonitored(h.id))
          FleetHostHealth(
            hostId: h.id,
            alias: h.alias,
            reachable: false,
            load1: 0,
            diskRootPercent: 0,
            failedUnitCount: 0,
            pendingUpdates: 0,
            fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            outcome: HostProbeOutcome.unchecked,
          )
        else
          _byId[h.id] ??
              FleetHostHealth(
                hostId: h.id,
                alias: h.alias,
                reachable: true,
                load1: 0,
                diskRootPercent: h.diskRootPercent ?? 0,
                failedUnitCount: h.failedUnitCount ?? 0,
                pendingUpdates: 0,
                fetchedAt: h.attentionAt ??
                    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
                fromCache: h.attentionAt != null,
              ),
    ];
    final filtered = filterFleetByTag(rows, tagsByHost, _tagFilter);
    final sorted = sortFleetHealth(filtered);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700 ? 4 : 3;

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Text('Fleet', style: KelolaType.display(color: c.text, size: 16)),
        actions: [
          TextButton(
            onPressed: _refreshing ? null : _refresh,
            child: Text(
              _refreshing ? 'Refreshing' : 'Refresh',
              style: KelolaType.body(color: c.amber, size: 13),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Text(
              'Tiles fill as hosts finish · read only · cap 5 · 10s',
              style: KelolaType.mono(color: c.dim, size: 9.5, letterSpacing: 0.5),
            ),
          ),
          if (plan.showChoosePrompt)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                'Choose up to $kFreeFleetHostLimit hosts to monitor.',
                style: KelolaType.body(color: c.muted, size: 13),
              ),
            ),
          if (_allTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  FilterPill(
                    label: 'all',
                    selected: _tagFilter == null,
                    onTap: () => setState(() => _tagFilter = null),
                  ),
                  for (final tag in _allTags)
                    FilterPill(
                      label: tag,
                      selected: _tagFilter == tag,
                      onTap: () => setState(() => _tagFilter = tag),
                    ),
                ],
              ),
            ),
          Expanded(
            child: hosts.isEmpty
                ? Center(
                    child: Text(
                      'No hosts yet.',
                      style: KelolaType.body(color: c.muted, size: 14),
                    ),
                  )
                : sorted.isEmpty
                    ? Center(
                        child: Text(
                          'No hosts with this tag.',
                          style: KelolaType.body(color: c.muted, size: 14),
                        ),
                      )
                    : GridView.builder(
                        padding: kelolaScrollPadding(
                          context,
                          left: 14,
                          top: 0,
                          right: 14,
                          extraBottom: 16,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: 104,
                        ),
                        itemCount: sorted.length,
                        itemBuilder: (context, i) {
                          final row = sorted[i];
                          final monitored = plan.isMonitored(row.hostId);
                          final host = hosts.firstWhere(
                            (h) => h.id == row.hostId,
                            orElse: () => Host(
                              id: row.hostId,
                              alias: row.alias,
                              address: '',
                              port: 22,
                              username: '',
                              keyAlias: '',
                            ),
                          );
                          return FleetHostTile(
                            alias: row.alias,
                            status: monitored
                                ? fleetTileHealthStatus(row)
                                : HealthStatus.unknown,
                            loading:
                                monitored && _loading.contains(row.hostId),
                            reachable: monitored && row.reachable,
                            downMessage: monitored
                                ? (row.reachable ? null : row.tileSummary())
                                : 'not monitored',
                            metrics: monitored
                                ? [
                                    for (final m in row.tileMetrics())
                                      FleetTileMetricView(
                                        label: m.label,
                                        value: m.value,
                                      ),
                                  ]
                                : const [],
                            onTap: () => openFleetHostSheet(
                              context,
                              ref,
                              host: host,
                              health: row,
                              onHealthUpdated: (updated) {
                                // Paint tile immediately; persist in background.
                                _applyHealth(updated);
                                ref
                                    .read(hostRepositoryProvider)
                                    .saveFleetCache(updated);
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
