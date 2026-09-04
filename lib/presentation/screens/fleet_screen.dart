import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/fleet_host_sheet.dart';
import 'package:kelola/providers.dart';

HealthStatus? fleetTileHealthStatus(FleetHostHealth h) {
  switch (h.severity) {
    case FleetSeverity.unreachable:
      return HealthStatus.unknown;
    case FleetSeverity.failedUnits:
    case FleetSeverity.badContainers:
    case FleetSeverity.loadHigh:
      return HealthStatus.failed;
    case FleetSeverity.diskHigh:
    case FleetSeverity.securityUpdates:
    case FleetSeverity.memHigh:
    case FleetSeverity.pendingUpdates:
    case FleetSeverity.rebootRequired:
      return HealthStatus.warning;
    case FleetSeverity.healthy:
      return HealthStatus.healthy;
  }
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
  String? _error;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
    await _refresh();
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
    setState(() {
      _refreshing = true;
      _error = null;
      _loading
        ..clear()
        ..addAll(hosts.map((h) => h.id));
      _allTags = {
        for (final h in hosts) ...h.tags,
      }.toList()
        ..sort();
    });

    await ref.read(enrollmentProvider.notifier).ensureKey();
    if (!mounted) {
      return;
    }

    await runPooled(
      hosts,
      concurrency: 5,
      timeout: const Duration(seconds: 10),
      fn: (host) async {
        const scope = ProbeScope.fleet;
        final probe = FleetHealthProbe(hostId: host.id, alias: host.alias);
        assertFleetReadOnly(probe, scope: scope);
        final health = await runHostProbe(
          ref: ref,
          context: context,
          host: host,
          probe: probe,
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
        );
        await ref.read(hostRepositoryProvider).saveFleetCache(live);
        if (!mounted) {
          return;
        }
        // Progressive: paint this tile as soon as the host finishes.
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
        );
        if (cached != null) {
          await ref.read(hostRepositoryProvider).saveFleetCache(unreachable);
        }
        if (!mounted) {
          return;
        }
        setState(() {
          _byId[host.id] = unreachable;
          _loading.remove(host.id);
          _error ??= describeSshError(error);
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
    final hostsAsync = ref.watch(hostsProvider);
    final hosts = hostsAsync.valueOrNull ?? const <Host>[];
    final tagsByHost = {for (final h in hosts) h.id: h.tags};

    final rows = <FleetHostHealth>[
      for (final h in hosts)
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
    // Prefer density: 3 cols on phone, 4 on wide — target 12–16 tiles without scroll.
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: KelolaError(message: _error!),
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
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          mainAxisExtent: 104,
                        ),
                        itemCount: sorted.length,
                        itemBuilder: (context, i) {
                          final row = sorted[i];
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
                            risk: row.tileRiskLevel,
                            status: fleetTileHealthStatus(row),
                            loading: _loading.contains(row.hostId),
                            reachable: row.reachable,
                            downMessage: row.reachable ? null : row.tileSummary(),
                            metrics: [
                              for (final m in row.tileMetrics())
                                FleetTileMetricView(
                                  label: m.label,
                                  value: m.value,
                                ),
                            ],
                            onTap: () => openFleetHostSheet(
                              context,
                              ref,
                              host: host,
                              health: row,
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
