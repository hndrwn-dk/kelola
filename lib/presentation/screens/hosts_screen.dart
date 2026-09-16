import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/design/style_guide_screen.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';
import 'package:kelola/domain/hosts/stable_host_inventory.dart';
import 'package:kelola/domain/incident/incident_sheet.dart';
import 'package:kelola/domain/widget/publish_home_widget.dart';
import 'package:kelola/domain/llm/settings.dart';
import 'package:kelola/presentation/fleet/fleet_probe_policy.dart';
import 'package:kelola/presentation/host_inventory_ping.dart';
import 'package:kelola/presentation/pro_locked_sheet.dart';
import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/fleet_screen.dart';
import 'package:kelola/presentation/screens/llm_settings_screen.dart';
import 'package:kelola/presentation/screens/search_screen.dart';
import 'package:kelola/presentation/screens/settings_screen.dart';
import 'package:kelola/presentation/widgets/confirm_remove_host.dart';
import 'package:kelola/presentation/widgets/host_list_actions.dart';
import 'package:kelola/presentation/widgets/incident_sheet.dart';
import 'package:kelola/providers.dart';

/// User-facing copy for a failed host list. Never the exception text.
String hostInventoryErrorCopy(Object error) {
  return 'Could not load hosts.';
}

class HostsScreen extends ConsumerStatefulWidget {
  const HostsScreen({super.key});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  AuditWeekSummary _audit = const AuditWeekSummary(
    changes: 0,
    destructive: 0,
    failed: 0,
  );
  var _widgetOn = false;
  final Set<HostInventoryBucket> _forceExpanded = {};
  final Set<HostInventoryBucket> _forceCollapsed = {};
  final _stableInventory = StableHostInventory();
  /// One-shot: pull-to-refresh finished probing and may re-bucket.
  var _allowInventoryReorder = false;

  bool _takeAllowReorder() {
    if (!_allowInventoryReorder) {
      return false;
    }
    _allowInventoryReorder = false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    final repo = ref.read(hostRepositoryProvider);
    final now = DateTime.now().toUtc();
    final rows = await repo.listAuditSince(
      now.subtract(const Duration(days: 7)),
    );
    final widgetOn = await repo.widgetEnabled();
    if (!mounted) {
      return;
    }
    setState(() {
      _audit = summarizeAudit(rows, now: now);
      _widgetOn = widgetOn;
    });
  }

  FleetProbePlan _plan(List<Host> hosts) {
    ref.watch(entitlementRevisionProvider);
    final selected = ref.watch(fleetProbeSelectionProvider).valueOrNull;
    return planFleetProbes(
      hostIds: [for (final host in hosts) host.id],
      selectedHostIds: selected,
      fleetUnlimited:
          ref.watch(entitlementProvider).isUnlocked(ProFeature.fleetUnlimited),
    );
  }

  Future<void> _openAddHost(FleetProbePlan plan, {required bool reloadAudit}) async {
    if (plan.addHostLocked) {
      await showProLockedSheet(
        context,
        title: 'Hosts',
        body: 'This build monitors up to $kFreeFleetHostLimit hosts. '
            'Unlock to add another.',
        onPurchase: () => ref.read(entitlementProvider).purchase(),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AddHostScreen(),
      ),
    );
    if (reloadAudit) {
      _loadAudit();
    } else {
      _reloadSideState();
    }
  }

  Future<void> _toggleProbe(
    Host host,
    FleetProbePlan plan,
    Set<String> selected,
  ) async {
    if (selected.contains(host.id)) {
      await ref.read(fleetProbeSelectionProvider.notifier).replace(
        {...selected}..remove(host.id),
      );
      return;
    }
    if (plan.selectingAnotherIsLocked(host.id)) {
      await showProLockedSheet(
        context,
        title: 'Fleet',
        body: 'This build monitors up to $kFreeFleetHostLimit hosts. '
            'Choose which three stay in the fleet probe.',
        onPurchase: () => ref.read(entitlementProvider).purchase(),
      );
      return;
    }
    await ref.read(fleetProbeSelectionProvider.notifier).replace(
      {...selected, host.id},
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hosts = ref.watch(hostsProvider);
    final lastHostId = ref.watch(lastHostIdProvider).valueOrNull;
    final pool = ref.watch(sessionPoolProvider);
    final liveList = hosts.valueOrNull;
    HostInventoryView? inventory;
    if (liveList != null && liveList.isNotEmpty) {
      inventory = _stableInventory.project(
        liveList,
        allowReorder: _takeAllowReorder(),
      );
    }
    final plan = _plan(liveList ?? const []);
    final displayed = inventory == null
        ? null
        : splitUnmonitored(inventory, plan.isMonitored);
    final summary = displayed?.summary;
    final selected =
        ref.watch(fleetProbeSelectionProvider).valueOrNull ?? const <String>{};

    return Scaffold(
      backgroundColor: c.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: HostsChromeAccent()),
          Column(
            children: [
              HostsRootBar(
                summary: summary,
                actions: [
                  if (kDebugMode)
                    IconButton(
                      tooltip: 'Style guide',
                      icon: const Icon(Icons.palette_outlined),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StyleGuideScreen(),
                          ),
                        );
                      },
                    ),
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search_rounded),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SearchScreen(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Add host',
                    icon: Icon(Icons.add_rounded, color: c.amber),
                    onPressed: () => _openAddHost(plan, reloadAudit: false),
                  ),
                ],
              ),
              Expanded(
                child: hosts.when(
                  data: (list) {
                    if (list.isEmpty) {
                      return RefreshIndicator(
                        color: c.amber,
                        onRefresh: () => _refresh(const []),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.45,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Kelola',
                                        style: KelolaType.display(
                                          color: c.text,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Add your first host. You'll need SSH access and a minute.",
                                        textAlign: TextAlign.center,
                                        style: KelolaType.body(
                                          color: c.muted,
                                          size: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton(
                                        onPressed: () => _openAddHost(
                                          plan,
                                          reloadAudit: true,
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: c.amber,
                                        ),
                                        child: Text(
                                          'Add host',
                                          style: KelolaType.display(
                                            color: c.ink,
                                            size: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final view = inventory ??
                        _stableInventory.project(
                          list,
                          allowReorder: false,
                        );
                    Host? resume;
                    if (lastHostId != null &&
                        pool.hasLiveSession(lastHostId)) {
                      for (final h in list) {
                        if (h.id == lastHostId) {
                          resume = h;
                          break;
                        }
                      }
                    }
                    return _inventory(
                      c,
                      list,
                      splitUnmonitored(view, plan.isMonitored),
                      resume,
                      plan,
                      selected,
                    );
                  },
                  loading: () => Center(
                    child: CircularProgressIndicator(color: c.amber),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: KelolaError(message: hostInventoryErrorCopy(e)),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Column(
                        children: [
                          ServiceRow(
                            risk: RiskLevel.read,
                            name: 'Fleet',
                            meta: 'health grid · read only',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const FleetScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 6),
                          ServiceRow(
                            risk: RiskLevel.read,
                            name: 'Assist',
                            meta: ref.watch(llmSettingsProvider).when(
                                  data: llmAssistFooterMeta,
                                  loading: () => 'LLM · …',
                                  error: (_, _) => 'LLM · none',
                                ),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const LlmSettingsScreen(),
                                ),
                              );
                              ref.invalidate(llmSettingsProvider);
                            },
                          ),
                          const SizedBox(height: 6),
                          ServiceRow(
                            risk: RiskLevel.read,
                            name: 'Home widget',
                            meta: _widgetOn
                                ? 'on · last refresh only'
                                : 'off · last refresh only',
                            onTap: _toggleWidget,
                          ),
                        ],
                      ),
                    ),
                    HostsColophon(
                      version: kelolaAppVersion,
                      sourceLabel: ref.watch(entitlementProvider).sourceLabel,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _groupExpanded(HostInventoryBucket bucket, int count) {
    if (_forceExpanded.contains(bucket)) {
      return true;
    }
    if (_forceCollapsed.contains(bucket)) {
      return false;
    }
    return !collapseInventoryGroup(bucket, count);
  }

  void _toggleGroup(HostInventoryBucket bucket, int count) {
    setState(() {
      if (_groupExpanded(bucket, count)) {
        _forceExpanded.remove(bucket);
        _forceCollapsed.add(bucket);
      } else {
        _forceCollapsed.remove(bucket);
        _forceExpanded.add(bucket);
      }
    });
  }

  Widget _inventory(
    KelolaColors c,
    List<Host> list,
    DisplayedInventory displayed,
    Host? resume,
    FleetProbePlan plan,
    Set<String> selected,
  ) {
    final view = displayed.monitored;
    return RefreshIndicator(
      color: c.amber,
      onRefresh: () => _refresh(list),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (auditInsightKind(_audit) != AuditInsightKind.empty) ...[
                  AuditInsightRow(
                    summary: _audit,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AuditScreen(),
                        ),
                      );
                      await _loadAudit();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                if (resume != null) ...[
                  ServiceRow(
                    risk: RiskLevel.read,
                    status: HealthStatus.warning,
                    name: 'Resume ${resume.alias}',
                    meta: resume.lastRttMs == null
                        ? 'session still up'
                        : 'session still up · ${resume.lastRttMs}ms',
                    compact: true,
                    onTap: () => _openHost(resume!),
                  ),
                  const SizedBox(height: 8),
                ],
                ..._groupBlock(
                  c,
                  HostInventoryBucket.needsAttention,
                  view.needsAttention,
                  plan,
                  selected,
                ),
                if (displayed.unmonitored.isNotEmpty) ...[
                  HostGroupTray(
                    label: 'Not monitored',
                    child: Column(
                      children: [
                        for (var i = 0; i < displayed.unmonitored.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          _hostRow(c, displayed.unmonitored[i], plan, selected),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                ..._groupBlock(
                  c,
                  HostInventoryBucket.healthy,
                  view.healthy,
                  plan,
                  selected,
                ),
                ..._groupBlock(
                  c,
                  HostInventoryBucket.notChecked,
                  view.notChecked,
                  plan,
                  selected,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _groupBlock(
    KelolaColors c,
    HostInventoryBucket bucket,
    List<Host> hosts,
    FleetProbePlan plan,
    Set<String> selected,
  ) {
    if (hosts.isEmpty) {
      return const [];
    }
    final expanded = _groupExpanded(bucket, hosts.length);
    if (!expanded) {
      return [
        CollapsedHostGroup(
          label: collapsedInventoryLabel(bucket, hosts.length),
          onTap: () => _toggleGroup(bucket, hosts.length),
        ),
        const SizedBox(height: 8),
      ];
    }
    final rows = hosts.length > inventoryCollapseAfter
        ? ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: hosts.length,
            itemBuilder: (context, i) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: i == hosts.length - 1 ? 0 : 8,
                ),
                child: _hostRow(c, hosts[i], plan, selected),
              );
            },
          )
        : Column(
            children: [
              for (var i = 0; i < hosts.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _hostRow(c, hosts[i], plan, selected),
              ],
            ],
          );
    return [
      HostGroupTray(
        label: inventoryGroupLabel(bucket),
        child: rows,
      ),
      const SizedBox(height: 8),
    ];
  }

  Widget _hostRow(
    KelolaColors c,
    Host host,
    FleetProbePlan plan,
    Set<String> selected,
  ) {
    final unmonitored = !plan.isMonitored(host.id);
    final health = unmonitored ? HealthStatus.unknown : _health(host);
    final pill = unmonitored ? 'not monitored' : incidentChipLabel(host);
    return Dismissible(
      key: ValueKey(host.id),
      direction: DismissDirection.horizontal,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        decoration: BoxDecoration(
          color: c.amber.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(KelolaRadii.md),
        ),
        child: Text(
          'EDIT',
          style: KelolaType.mono(
            color: c.amber,
            size: 11,
            weight: FontWeight.w500,
          ),
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: c.red.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(KelolaRadii.md),
        ),
        child: Text(
          'REMOVE',
          style: KelolaType.mono(
            color: c.red,
            size: 11,
            weight: FontWeight.w500,
          ),
        ),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await _editHost(host);
        } else {
          await _deleteHost(host);
        }
        return false;
      },
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.25,
        DismissDirection.endToStart: 0.25,
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ServiceRow(
            risk: RiskLevel.read,
            status: health,
            leading: OsIcon.forOsId(host.osId),
            name: host.alias,
            meta: unmonitored ? host.endpoint : host.subtitle,
            pillText: pill,
            pillStatus: health,
            compact: true,
            onTap: () => _openHost(host),
            onPillTap: unmonitored || pill == null
                ? null
                : () => openHostIncident(context, ref, host),
            onLongPress: () => _hostActions(host),
          ),
          if (plan.showProbeToggles)
            Align(
              alignment: Alignment.centerRight,
              child: ModePill(
                key: Key('probe-toggle-${host.id}'),
                label: selected.contains(host.id) ? 'monitored' : 'monitor',
                active: selected.contains(host.id),
                onTap: () => _toggleProbe(host, plan, selected),
              ),
            ),
        ],
      ),
    );
  }

  HealthStatus _health(Host host) {
    if (host.attentionAt == null || host.isAttentionStale()) {
      return HealthStatus.unknown;
    }
    return switch (host.attention) {
      HostAttention.failedUnits => HealthStatus.failed,
      HostAttention.diskHigh => HealthStatus.warning,
      HostAttention.unreachable => HealthStatus.unknown,
      HostAttention.healthy => HealthStatus.healthy,
      HostAttention.unknown => HealthStatus.unknown,
    };
  }

  void _reloadSideState() {
    _loadAudit();
  }

  Future<void> _refresh(List<Host> hosts) async {
    final repo = ref.read(hostRepositoryProvider);
    final pool = ref.read(sessionPoolProvider);
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
    } catch (_) {
      // Ping still runs; SSH will fail per host if the key is missing.
    }
    await runPooled(
      hosts,
      concurrency: 5,
      timeout: const Duration(seconds: 10),
      fn: (host) async {
        final ping = await probeInventoryHost(
          pool: pool,
          repo: repo,
          host: host,
        );
        await storeInventoryPing(repo: repo, host: host, ping: ping);
      },
      onItemDone: (host, error) async {
        if (error != null) {
          await storeInventoryPingFailed(repo: repo, host: host);
        }
      },
    );
    await publishHomeWidget(
      repo: repo,
      bridge: ref.read(homeWidgetBridgeProvider),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _allowInventoryReorder = true;
    });
    _loadAudit();
  }

  Future<void> _toggleWidget() async {
    final next = !_widgetOn;
    final repo = ref.read(hostRepositoryProvider);
    await repo.setWidgetEnabled(next);
    await publishHomeWidget(
      repo: repo,
      bridge: ref.read(homeWidgetBridgeProvider),
    );
    if (mounted) {
      setState(() => _widgetOn = next);
    }
  }

  Future<void> _deleteHost(Host host) async {
    if (!await confirmRemoveHost(context, host.alias)) {
      return;
    }
    await ref.read(sessionPoolProvider).disconnect(host.id);
    await ref.read(hostRepositoryProvider).delete(host.id);
    _reloadSideState();
  }

  Future<void> _editHost(Host host) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditHostScreen(hostId: host.id),
      ),
    );
    _reloadSideState();
  }

  Future<void> _hostActions(Host host) {
    return showHostListActions(
      context,
      alias: host.alias,
      onEdit: () => _editHost(host),
      onRemove: () => _deleteHost(host),
    );
  }

  Future<void> _openHost(Host host) async {
    await ref.read(hostRepositoryProvider).setLastHost(host.id);
    await ref.read(hostRepositoryProvider).touchRecent(host);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDashboardScreen(hostId: host.id),
      ),
    );
    _reloadSideState();
  }
}
