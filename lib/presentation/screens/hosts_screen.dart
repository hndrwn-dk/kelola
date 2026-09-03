import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/app_version.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/design/style_guide_screen.dart';
import 'package:kelola/domain/audit/audit_view.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';
import 'package:kelola/domain/incident/incident_sheet.dart';
import 'package:kelola/presentation/host_inventory_ping.dart';
import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/search_screen.dart';
import 'package:kelola/presentation/widgets/confirm_remove_host.dart';
import 'package:kelola/presentation/widgets/host_list_actions.dart';
import 'package:kelola/presentation/widgets/incident_sheet.dart';
import 'package:kelola/providers.dart';

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
  final Set<HostInventoryBucket> _forceExpanded = {};
  final Set<HostInventoryBucket> _forceCollapsed = {};

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    final rows = await ref.read(hostRepositoryProvider).listAudit();
    if (!mounted) {
      return;
    }
    setState(() {
      _audit = summarizeAudit(rows, now: DateTime.now().toUtc());
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hosts = ref.watch(hostsProvider);
    final lastHostId = ref.watch(lastHostIdProvider).valueOrNull;
    final pool = ref.watch(sessionPoolProvider);
    final summary = hosts.maybeWhen(
      data: (list) =>
          list.isEmpty ? null : HostInventoryView.build(list).summary,
      orElse: () => null,
    );

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
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AddHostScreen(),
                        ),
                      );
                      _invalidate();
                    },
                  ),
                ],
              ),
              Expanded(
                child: hosts.when(
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
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
                                "Add your first server. You'll need SSH access and a minute.",
                                textAlign: TextAlign.center,
                                style: KelolaType.body(color: c.muted, size: 14),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const AddHostScreen(),
                                    ),
                                  );
                                },
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
                      );
                    }
                    final view = HostInventoryView.build(list);
                    Host? resume;
                    if (lastHostId != null && pool.hasLiveSession(lastHostId)) {
                      for (final h in list) {
                        if (h.id == lastHostId) {
                          resume = h;
                          break;
                        }
                      }
                    }
                    return _inventory(c, list, view, resume);
                  },
                  loading: () => Center(
                    child: CircularProgressIndicator(color: c.amber),
                  ),
                  error: (e, _) => Center(
                    child: Text(
                      '$e',
                      style: KelolaType.body(color: c.red, size: 13),
                    ),
                  ),
                ),
              ),
              const SafeArea(
                top: false,
                child: HostsColophon(version: kelolaAppVersion),
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
    HostInventoryView view,
    Host? resume,
  ) {
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
                ),
                ..._groupBlock(
                  c,
                  HostInventoryBucket.healthy,
                  view.healthy,
                ),
                ..._groupBlock(
                  c,
                  HostInventoryBucket.notChecked,
                  view.notChecked,
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
                child: _hostRow(c, hosts[i]),
              );
            },
          )
        : Column(
            children: [
              for (var i = 0; i < hosts.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _hostRow(c, hosts[i]),
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

  Widget _hostRow(KelolaColors c, Host host) {
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
      child: ServiceRow(
        risk: RiskLevel.read,
        status: _health(host),
        leading: OsIcon.forOsId(host.osId),
        name: host.alias,
        meta: host.subtitle,
        detail: hostInventoryDetail(host),
        pillText: incidentChipLabel(host),
        pillStatus: _health(host),
        compact: true,
        onTap: () => _openHost(host),
        onPillTap: incidentChipLabel(host) == null
            ? null
            : () => openHostIncident(context, ref, host),
        onLongPress: () => _hostActions(host),
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

  void _invalidate() {
    ref.invalidate(hostsProvider);
    ref.invalidate(recentsProvider);
    ref.invalidate(lastHostIdProvider);
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
        if (mounted) {
          _invalidate();
        }
      },
    );
  }

  Future<void> _deleteHost(Host host) async {
    if (!await confirmRemoveHost(context, host.alias)) {
      return;
    }
    await ref.read(sessionPoolProvider).disconnect(host.id);
    await ref.read(hostRepositoryProvider).delete(host.id);
    _invalidate();
  }

  Future<void> _editHost(Host host) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditHostScreen(hostId: host.id),
      ),
    );
    _invalidate();
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
    _invalidate();
  }
}
