import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/entitlement/entitlement.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/serial_mask.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/dashboard_status.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/widget/publish_home_widget.dart';
import 'package:kelola/presentation/destructive_auth.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/nav.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/containers_screen.dart';
import 'package:kelola/presentation/screens/disk_screen.dart';
import 'package:kelola/presentation/screens/firewall_screen.dart';
import 'package:kelola/presentation/screens/files_screen.dart';
import 'package:kelola/presentation/screens/packages_screen.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/journal_screen.dart';
import 'package:kelola/presentation/screens/metrics_screen.dart';
import 'package:kelola/presentation/screens/network_screen.dart';
import 'package:kelola/presentation/screens/processes_screen.dart';
import 'package:kelola/presentation/screens/terminal_sheet.dart';
import 'package:kelola/presentation/screens/snippets_screen.dart';
import 'package:kelola/presentation/screens/tunnels_screen.dart';
import 'package:kelola/presentation/screens/units_screen.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';
import 'package:kelola/presentation/widgets/confirm_remove_host.dart';
import 'package:kelola/presentation/widgets/diagnostic_pack_sheet.dart';
import 'package:kelola/presentation/widgets/incident_sheet.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

List<double> normalizeSparkPercents(List<double> percents) {
  return [for (final v in percents) (v / 100).clamp(0.0, 1.0)];
}

double? loadMeterFraction(double load1, int? nprocCores) {
  if (nprocCores == null || nprocCores <= 0) {
    return null;
  }
  return (load1 / nprocCores).clamp(0.0, 1.0);
}

HealthStatus loadHealth(double load1, int? nprocCores) {
  if (nprocCores == null || nprocCores <= 0) {
    return HealthStatus.unknown;
  }
  if (load1 >= nprocCores) {
    return HealthStatus.failed;
  }
  if (load1 >= nprocCores * 0.75) {
    return HealthStatus.warning;
  }
  return HealthStatus.healthy;
}

/// OS pretty name for the host app-bar subtitle. Null when unknown.
String? dashboardOsTitle(String? os) {
  final label = (os ?? '').trim();
  if (label.isEmpty || label == 'unknown') {
    return null;
  }
  return label;
}

/// App-bar subtitle: OS identity and uptime. When both are present, drop a
/// trailing parenthetical codename first so uptime stays visible.
String? dashboardAppBarSubtitle({String? os, String? uptime}) {
  final full = dashboardOsTitle(os);
  final up = (uptime == null || uptime.isEmpty) ? null : 'Uptime $uptime';
  if (full == null) {
    return up;
  }
  if (up == null) {
    return full;
  }
  final short = full.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim();
  final osPart = short.isEmpty ? full : short;
  return '$osPart · $up';
}

String? formatDashboardCpuDenom(int? nprocCores) {
  if (nprocCores == null || nprocCores <= 0) {
    return null;
  }
  return nprocCores == 1 ? '1 core' : '$nprocCores cores';
}

/// Same shape as Disk screen mount lines: `x.x / y.y GiB`.
String formatDashboardGiBPair({required int kibUsed, required int kibTotal}) {
  String g(int kib) => (kib / 1024 / 1024).toStringAsFixed(1);
  return '${g(kibUsed)} / ${g(kibTotal)} GiB';
}

class HostDashboardScreen extends ConsumerStatefulWidget {
  const HostDashboardScreen({
    super.key,
    required this.hostId,
    this.openIncident = false,
  });

  final String hostId;
  final bool openIncident;

  @override
  ConsumerState<HostDashboardScreen> createState() =>
      _HostDashboardScreenState();
}

class _HostDashboardScreenState extends ConsumerState<HostDashboardScreen> {
  Host? _host;
  HostFacts? _facts;
  DashboardSnapshot? _dash;
  int? _pendingUpdates;
  String? _error;
  bool _loading = true;
  var _openedIncident = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = dashboardErrorAfterRefreshStart(_error);
    });
    try {
      final repo = ref.read(hostRepositoryProvider);
      final host = await repo.get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      _host = host;
      var facts = await repo.facts(host.id);
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final sw = Stopwatch()..start();
      // Cached facts when present — never re-run HostFactsProbe (and never
      // re-attempt privileged DMI) on every dashboard open.
      if (facts == null || facts.osId.isEmpty) {
        final probed = await runHostProbe(
          ref: ref,
          context: context,
          host: host,
          probe: const HostFactsProbe(),
        );
        facts = probed;
        await repo.saveFacts(host.id, probed);
        if (!mounted) {
          return;
        }
      }
      final knownFacts = facts!;
      _facts = knownFacts;
      final dash = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DashboardProbe(),
        facts: knownFacts,
      );
      final fleetCache = await repo.loadFleetCacheByHost();
      final pending = fleetCache[host.id]?.pendingUpdates;
      sw.stop();
      final now = DateTime.now().toUtc();
      final attention = switch (dash.attention) {
        HostAttentionFromSnapshot.failedUnits => HostAttention.failedUnits,
        HostAttentionFromSnapshot.diskHigh => HostAttention.diskHigh,
        HostAttentionFromSnapshot.healthy => HostAttention.healthy,
      };
      await repo.updateAttention(
        id: host.id,
        attention: attention,
        lastSeenAt: now,
        rttMs: sw.elapsedMilliseconds,
        failedUnitCount: dash.failedUnitCount,
        diskRootPercent: dash.diskRootPercent,
        attentionAt: now,
      );
      await publishHomeWidget(
        repo: repo,
        bridge: ref.read(homeWidgetBridgeProvider),
      );
      final updated = await repo.get(host.id);
      setState(() {
        _facts = facts;
        _dash = dash;
        _pendingUpdates = fleetCache.containsKey(host.id) ? pending : null;
        _host = updated ?? host;
        _error = dashboardErrorAfterSuccessfulPoll(_error);
      });
    } on HostKeyMismatchException catch (e) {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostKeyMismatchScreen(
            hostAlias: _host?.alias ?? widget.hostId,
            pinned: e.pinnedFingerprint,
            seen: e.seenFingerprint,
          ),
        ),
      );
    } catch (e) {
      await ref.read(hostRepositoryProvider).updateAttention(
            id: widget.hostId,
            attention: HostAttention.unreachable,
          );
      await publishHomeWidget(
        repo: ref.read(hostRepositoryProvider),
        bridge: ref.read(homeWidgetBridgeProvider),
      );
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _maybeOpenIncident();
      }
    }
  }

  void _maybeOpenIncident() {
    if (!widget.openIncident || _openedIncident) {
      return;
    }
    final host = _host;
    if (host == null) {
      return;
    }
    _openedIncident = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      openHostIncident(context, ref, host);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final host = _host;
    final dash = _dash;
    final facts = _facts;

    final subtitle = dashboardAppBarSubtitle(
      os: facts?.label,
      uptime: dash == null ? null : _formatUp(dash.uptime),
    );

    return KelolaPage(
      title: host?.alias ?? 'Host',
      bar: KelolaHostAppBar(
        hostAlias: host?.alias ?? '',
        title: subtitle ?? '',
        actions: [
          HostDashboardMenuButton(
            onNote: _editNote,
            onEdit: _openEdit,
            onDetails: _openDetails,
            onDiagnostic: host == null
                ? null
                : () => openDiagnosticPack(context, ref, host),
            onAudit: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AuditScreen(hostId: widget.hostId),
                ),
              );
            },
            onRemove: host == null ? () {} : () => _deleteHost(host),
          ),
        ],
      ),
      busy: _loading,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: kelolaScrollPadding(context, top: 8),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: KelolaError(
                  message: _error!,
                  sudoUser: host?.username,
                  onDismiss: () => setState(() => _error = null),
                ),
              ),
            if (dash != null && dash.failedUnitCount > 0) ...[
              ServiceRow(
                risk: RiskLevel.read,
                status: HealthStatus.failed,
                name: '${dash.failedUnitCount} units failed',
                meta: dash.failedUnitNames.isEmpty
                    ? 'open incident'
                    : dash.failedUnitNames.join(' · '),
                pillText: '${dash.failedUnitCount} failed',
                onTap: host == null
                    ? null
                    : () => openHostIncident(
                          context,
                          ref,
                          host,
                          failedUnitNames: dash.failedUnitNames,
                        ),
              ),
              const SizedBox(height: 8),
            ] else if (dash != null && dash.diskRootPercent >= 90) ...[
              ServiceRow(
                risk: RiskLevel.read,
                status: HealthStatus.warning,
                name: '/ at ${dash.diskRootPercent}%',
                meta: 'open incident',
                pillText: 'disk ${dash.diskRootPercent}%',
                onTap: host == null
                    ? null
                    : () => openHostIncident(context, ref, host),
              ),
              const SizedBox(height: 8),
            ],
            if (host != null &&
                host.note != null &&
                host.note!.trim().isNotEmpty) ...[
              RiskBand(
                risk: RiskLevel.read,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'NOTE',
                      style: KelolaType.mono(
                        color: c.dim,
                        size: 8.5,
                        letterSpacing: 0.9,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      host.note!,
                      style: KelolaType.body(color: c.text, size: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (dash != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _open(
                        (id) => MetricsScreen(
                          hostId: id,
                          focus: MetricsFocus.cpu,
                        ),
                      ),
                      child: StatCard(
                        label: 'CPU',
                        value: dash.cpuPercent.round().toString(),
                        unit: '%',
                        detail: formatDashboardCpuDenom(
                          dash.nprocCores ?? facts?.nprocCores,
                        ),
                        meterFraction: (dash.cpuPercent / 100).clamp(0, 1),
                        status: _pctHealth(dash.cpuPercent.round()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () => _open(
                        (id) => MetricsScreen(
                          hostId: id,
                          focus: MetricsFocus.memory,
                        ),
                      ),
                      child: StatCard(
                        label: 'Memory',
                        value: '${dash.memUsedPercent}',
                        unit: '%',
                        detail: dash.mem.totalKb > 0
                            ? formatDashboardGiBPair(
                                kibUsed: dash.mem.usedKb,
                                kibTotal: dash.mem.totalKb,
                              )
                            : null,
                        meterFraction: dash.mem.meterFraction,
                        status: _pctHealth(dash.memUsedPercent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      onTap: () => _open((id) => DiskScreen(hostId: id)),
                      child: StatCard(
                        label: 'Disk /',
                        value: '${dash.diskRootPercent}',
                        unit: '%',
                        detail: dash.diskRootTotalKib > 0
                            ? formatDashboardGiBPair(
                                kibUsed: dash.diskRootUsedKib,
                                kibTotal: dash.diskRootTotalKib,
                              )
                            : null,
                        meterFraction: dash.diskRootPercent / 100,
                        status: _pctHealth(dash.diskRootPercent),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DashboardLoadCard(
                load1: dash.load1,
                load5: dash.load5,
                load15: dash.load15,
              ),
              if (_pendingUpdates != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _open((id) => PackagesScreen(hostId: id)),
                  child: StatCard(
                    label: 'Updates',
                    value: '$_pendingUpdates',
                    status: _pendingUpdates! > 0
                        ? HealthStatus.warning
                        : HealthStatus.healthy,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 14),
            Text(
              'TOOLS',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ToolTile(
                    label: 'Services',
                    meta: 'systemd',
                    onTap: () => _openUnits(
                      failedOnly: dash != null && dash.failedUnitCount > 0,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Logs',
                    meta: 'journalctl',
                    onTap: () => _open((id) => JournalScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Disk',
                    meta: 'df',
                    onTap: () => _open((id) => DiskScreen(hostId: id)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: ToolTile(
                    label: 'Processes',
                    meta: 'ps',
                    onTap: () => _open((id) => ProcessesScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Containers',
                    meta: 'containers',
                    onTap: () => _open((id) => ContainersScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Packages',
                    meta: 'updates',
                    onTap: () => _open((id) => PackagesScreen(hostId: id)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: ToolTile(
                    label: 'Firewall',
                    meta: 'rules',
                    onTap: () => _open((id) => FirewallScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Network',
                    meta: 'ip ss',
                    onTap: () => _open((id) => NetworkScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Files',
                    meta: 'sftp',
                    onTap: () => _open((id) => FilesScreen(hostId: id)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: ToolTile(
                    label: 'Tunnels',
                    meta: _tunnelsMeta(ref),
                    onTap: () {
                      final unlocked = ref
                          .read(entitlementProvider)
                          .isUnlocked(ProFeature.tunnels);
                      if (!unlocked) {
                        showTunnelsLockedExplainer(
                          context,
                          onPurchase: () =>
                              ref.read(entitlementProvider).purchase(),
                        );
                        return;
                      }
                      _open((id) => TunnelsScreen(hostId: id));
                    },
                  ),
                ),
                const SizedBox(width: 7),
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: 7),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            if (host != null) ...[
              const SizedBox(height: 14),
              Text(
                'HOST',
                style: KelolaType.mono(
                  color: c.dim,
                  size: 8.5,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 8),
                ServiceRow(
                risk: RiskLevel.mutate,
                name: 'Terminal',
                meta: 'no PTY · audited',
                onTap: () => openCommandSheet(context, ref, host),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.read,
                name: 'Snippets',
                meta: 'templates · never fleet',
                onTap: () => _open((_) => SnippetsScreen(host: host)),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.mutate,
                name: 'Flush caches',
                meta: 'mutate · sudo -n drop_caches',
                onTap: () => _hostVerb(
                  host,
                  HostVerb.dropCaches,
                  title: 'Flush page cache?',
                  body:
                      'Runs sync and writes 3 to drop_caches on ${host.alias}. Needs sudo -n.',
                  confirm: 'Flush',
                  risk: RiskLevel.mutate,
                ),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.destructive,
                name: 'Reboot',
                meta: 'destructive · SSH will drop',
                onTap: () => _hostVerb(
                  host,
                  HostVerb.reboot,
                  title: 'Reboot ${host.alias}?',
                  body:
                      'The host will reboot. SSH will drop until it comes back.',
                  confirm: 'Reboot',
                  risk: RiskLevel.destructive,
                ),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.destructive,
                name: 'Power off',
                meta: 'destructive · SSH will drop',
                onTap: () => _hostVerb(
                  host,
                  HostVerb.poweroff,
                  title: 'Power off ${host.alias}?',
                  body: 'The host will shut down. SSH will drop.',
                  confirm: 'Poweroff',
                  risk: RiskLevel.destructive,
                ),
              ),
            ],
            if (host != null) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _toggleReadOnly(host),
                behavior: HitTestBehavior.opaque,
                child: DashboardStatusLine(
                  checkedAt: host.attentionAt,
                  readOnly: host.readOnly,
                  sudoNeedsPassword: host.sudoNeedsPassword,
                  sudoUser: host.username,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _tunnelsMeta(WidgetRef ref) {
    final tunnels = ref.watch(activeTunnelsProvider).valueOrNull ?? const [];
    final n = tunnels
        .where(
          (t) =>
              t.target.hostId == widget.hostId &&
              t.state != TunnelState.closed &&
              t.state != TunnelState.failed,
        )
        .length;
    if (n <= 0) return 'forward';
    return n == 1 ? '1 active' : '$n active';
  }

  HealthStatus _pctHealth(int percent) {
    if (percent >= 90) return HealthStatus.failed;
    if (percent >= 75) return HealthStatus.warning;
    return HealthStatus.healthy;
  }

  Future<void> _open(Widget Function(String hostId) builder) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => builder(widget.hostId)),
    );
  }

  Future<void> _editNote() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final ctrl = TextEditingController(text: host.note ?? '');
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.kc.ink,
      builder: (ctx) {
        return KelolaSheet(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Host note',
                style: KelolaType.display(color: ctx.kc.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Local only. Searchable. Not sent to the host.',
                style: KelolaType.body(color: ctx.kc.muted, size: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                style: KelolaType.body(color: ctx.kc.text, size: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                style: FilledButton.styleFrom(backgroundColor: ctx.kc.amber),
                child: Text(
                  'Save',
                  style: KelolaType.display(color: ctx.kc.ink, size: 13),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    if (saved == null) {
      return;
    }
    await ref.read(hostRepositoryProvider).updateNote(
          host.id,
          saved.trim().isEmpty ? null : saved.trim(),
        );
    await _refresh();
  }

  Future<void> _openEdit() async {
    final host = _host;
    if (host == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditHostScreen(hostId: host.id),
      ),
    );
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() => _host = updated ?? host);
  }

  Future<void> _openDetails() async {
    final host = _host;
    if (host == null) {
      return;
    }
    final pinned =
        await ref.read(hostRepositoryProvider).pinnedKey(host.id);
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDetailsScreen(
          host: host,
          facts: _facts ?? HostFacts.undiscovered,
          pinnedKey: pinned,
          connected: ref.read(sessionPoolProvider).hasLiveSession(host.id),
          onEdit: _openEdit,
          onRevealSerial: () {
            return ref.read(hostRepositoryProvider).recordAudit(
              hostId: host.id,
              hostAlias: host.alias,
              remoteUser: host.username,
              title: revealedSerialAuditTitle,
              command: revealedSerialAuditCommand,
              risk: RiskLevel.read.name,
              usedSudo: false,
            );
          },
        ),
      ),
    );
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() => _host = updated ?? host);
  }

  Future<void> _openUnits({required bool failedOnly}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnitsScreen(
          hostId: widget.hostId,
          failedOnly: failedOnly,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _toggleReadOnly(Host host) async {
    final turningOn = !host.readOnly;
    final ok = await showMutateConfirm(
      context,
      title: turningOn
          ? 'Make ${host.alias} read-only?'
          : 'Allow writes on ${host.alias}?',
      body: turningOn
          ? 'Reboot, Flush caches, and other changes will be blocked until you turn this off.'
          : 'Reboot, Flush caches, and other mutate actions will run again.',
      confirmLabel: turningOn ? 'Read-only' : 'Allow writes',
    );
    if (!ok || !mounted) {
      return;
    }
    await ref.read(hostRepositoryProvider).setReadOnly(host.id, turningOn);
    final updated = await ref.read(hostRepositoryProvider).get(host.id);
    if (!mounted) {
      return;
    }
    setState(() => _host = updated ?? host);
  }

  Future<void> _deleteHost(Host host) async {
    if (!await confirmRemoveHost(context, host.alias)) {
      return;
    }
    await ref.read(sessionPoolProvider).disconnect(host.id);
    await ref.read(hostRepositoryProvider).delete(host.id);
    if (!mounted) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      openHostsRoot(context);
    }
  }

  Future<void> _hostVerb(
    Host host,
    HostVerb verb, {
    required String title,
    required String body,
    required String confirm,
    required RiskLevel risk,
  }) async {
    final ok = await confirmHostAction(
      context,
      hostAlias: host.alias,
      title: title,
      body: body,
      confirmLabel: confirm,
      risk: risk,
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      await requireDestructivePresence(
        ref.read(hardwareSignerProvider),
        risk: risk,
        reason: title,
      );
      if (!mounted) {
        return;
      }
      final msg = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: HostActionProbe(verb),
        facts: _facts,
      );
      if (verb == HostVerb.reboot || verb == HostVerb.poweroff) {
        await ref.read(sessionPoolProvider).disconnect(host.id);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (verb == HostVerb.reboot || verb == HostVerb.poweroff) {
        await ref.read(sessionPoolProvider).disconnect(host.id);
      }
      if (!mounted) {
        return;
      }
      final updated = await ref.read(hostRepositoryProvider).get(host.id);
      setState(() {
        _error = describeSshError(e);
        if (updated != null) {
          _host = updated;
        }
      });
    }
  }

  static String _formatUp(Duration d) {
    final days = d.inDays;
    if (days > 0) {
      return '${days}d';
    }
    return '${d.inHours}h';
  }
}

class HostDashboardMenuButton extends StatelessWidget {
  const HostDashboardMenuButton({
    super.key,
    required this.onNote,
    required this.onEdit,
    required this.onDetails,
    required this.onAudit,
    required this.onRemove,
    this.onDiagnostic,
  });

  final VoidCallback onNote;
  final VoidCallback onEdit;
  final VoidCallback onDetails;
  final VoidCallback onAudit;
  final VoidCallback onRemove;
  final VoidCallback? onDiagnostic;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      child: Builder(
        builder: (context) =>
            KelolaChromeIconButton.plate(context, Icons.more_vert_rounded),
      ),
      onSelected: (v) {
        switch (v) {
          case 'note':
            onNote();
          case 'edit':
            onEdit();
          case 'details':
            onDetails();
          case 'diagnostic':
            onDiagnostic?.call();
          case 'audit':
            onAudit();
          case 'delete':
            onRemove();
        }
      },
      itemBuilder: (context) {
        final c = context.kc;
        return [
          const PopupMenuItem(value: 'note', child: Text('Note')),
          const PopupMenuItem(value: 'edit', child: Text('Edit host')),
          const PopupMenuItem(value: 'details', child: Text('Host details')),
          if (onDiagnostic != null)
            const PopupMenuItem(
              value: 'diagnostic',
              child: Text('Diagnostic pack'),
            ),
          const PopupMenuItem(value: 'audit', child: Text('Audit log')),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              'Remove host',
              style: TextStyle(color: c.red),
            ),
          ),
        ];
      },
    );
  }
}
