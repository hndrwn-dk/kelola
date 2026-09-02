import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/design/style_guide_screen.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';
import 'package:kelola/domain/hosts/pooled_run.dart';
import 'package:kelola/presentation/host_inventory_ping.dart';
import 'package:kelola/presentation/screens/add_host_screen.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/search_screen.dart';
import 'package:kelola/presentation/widgets/confirm_remove_host.dart';
import 'package:kelola/presentation/widgets/host_list_actions.dart';
import 'package:kelola/providers.dart';

class HostsScreen extends ConsumerStatefulWidget {
  const HostsScreen({super.key});

  @override
  ConsumerState<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends ConsumerState<HostsScreen> {
  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hosts = ref.watch(hostsProvider);
    final lastHostId = ref.watch(lastHostIdProvider).valueOrNull;
    final pool = ref.watch(sessionPoolProvider);

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: hosts.maybeWhen(
          data: (list) {
            if (list.isEmpty) {
              return Text(
                'Hosts',
                style: KelolaType.display(color: c.text, size: 16),
              );
            }
            final view = HostInventoryView.build(list);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hosts',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                Text(
                  view.summary,
                  style: KelolaType.body(color: c.dim, size: 12),
                ),
              ],
            );
          },
          orElse: () => Text(
            'Hosts',
            style: KelolaType.display(color: c.text, size: 16),
          ),
        ),
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
            tooltip: 'Audit',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AuditScreen(),
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
      body: hosts.when(
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
                      style: KelolaType.display(color: c.text, size: 22),
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
                      style: FilledButton.styleFrom(backgroundColor: c.amber),
                      child: Text(
                        'Add host',
                        style: KelolaType.display(color: c.ink, size: 13),
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
          return RefreshIndicator(
            color: c.amber,
            onRefresh: () => _refresh(list),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
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
                if (view.needsAttention.isNotEmpty) ...[
                  const SectionSlab('Needs attention'),
                  for (final host in view.needsAttention) _hostRow(c, host),
                ],
                if (view.healthy.isNotEmpty) ...[
                  const SectionSlab('Healthy'),
                  for (final host in view.healthy) _hostRow(c, host),
                ],
                if (view.notChecked.isNotEmpty) ...[
                  const SectionSlab('Not checked'),
                  for (final host in view.notChecked) _hostRow(c, host),
                ],
              ],
            ),
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: c.amber),
        ),
        error: (e, _) => Center(
          child: Text('$e', style: KelolaType.body(color: c.red, size: 13)),
        ),
      ),
    );
  }

  Widget _hostRow(KelolaColors c, Host host) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Dismissible(
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
          compact: true,
          onTap: () => _openHost(host),
          onLongPress: () => _hostActions(host),
        ),
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
