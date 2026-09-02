import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/metrics_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/nav.dart';
import 'package:kelola/presentation/screens/audit_screen.dart';
import 'package:kelola/presentation/screens/containers_screen.dart';
import 'package:kelola/presentation/screens/disk_screen.dart';
import 'package:kelola/presentation/screens/host_key_mismatch_screen.dart';
import 'package:kelola/presentation/screens/host_details_screen.dart';
import 'package:kelola/presentation/screens/edit_host_screen.dart';
import 'package:kelola/presentation/screens/journal_screen.dart';
import 'package:kelola/presentation/screens/metrics_screen.dart';
import 'package:kelola/presentation/screens/processes_screen.dart';
import 'package:kelola/presentation/screens/terminal_sheet.dart';
import 'package:kelola/presentation/screens/units_screen.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';
import 'package:kelola/presentation/widgets/confirm_remove_host.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart' show keyBackendLabel;
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

class HostDashboardScreen extends ConsumerStatefulWidget {
  const HostDashboardScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<HostDashboardScreen> createState() =>
      _HostDashboardScreenState();
}

class _HostDashboardScreenState extends ConsumerState<HostDashboardScreen> {
  Host? _host;
  HostFacts? _facts;
  DashboardSnapshot? _dash;
  String? _error;
  bool _loading = true;
  final _cpu = <double>[];
  Timer? _cpuTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cpuTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(hostRepositoryProvider);
      final host = await repo.get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      _host = host;
      _facts = await repo.facts(host.id);
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final sw = Stopwatch()..start();
      final facts = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
      await repo.saveFacts(host.id, facts);
      if (!mounted) {
        return;
      }
      final dash = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const DashboardProbe(),
        facts: facts,
      );
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
      final updated = await repo.get(host.id);
      setState(() {
        _facts = facts;
        _dash = dash;
        _host = updated ?? host;
        _cpu
          ..clear()
          ..add(dash.cpuPercent);
      });
      _armCpu();
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
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _armCpu() {
    _cpuTimer?.cancel();
    _cpuTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tickCpu());
  }

  Future<void> _tickCpu() async {
    final host = _host;
    final facts = _facts;
    if (host == null || !mounted) {
      return;
    }
    try {
      final cpu = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const CpuTickProbe(),
        facts: facts,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _cpu.add(cpu);
        if (_cpu.length > 40) {
          _cpu.removeAt(0);
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final host = _host;
    final dash = _dash;
    final facts = _facts;
    final cpuNow = _cpu.isEmpty ? (dash?.cpuPercent ?? 0) : _cpu.last;
    final spark = normalizeSparkPercents(_cpu);

    final machine = [
      if (facts != null) facts.label,
      if (dash != null) 'up ${_formatUp(dash.uptime)}',
      if (host != null &&
          ref.watch(sessionPoolProvider).hasLiveSession(host.id))
        host.lastRttMs == null ? 'session' : '${host.lastRttMs}ms',
      if (ref.watch(enrollmentProvider).backendLabel != null)
        keyBackendLabel(ref.watch(enrollmentProvider).backendLabel),
    ].join(' · ').toUpperCase();
    final readOnly = host?.readOnly == true;
    final showKicker = machine.isNotEmpty || readOnly;

    return KelolaPage(
      title: host?.alias ?? 'Host',
      kickerWidget: showKicker
          ? KickerLine(
              machine: machine,
              readOnly: readOnly,
              onToggleReadOnly:
                  host == null ? null : () => _toggleReadOnly(host),
            )
          : null,
      busy: _loading,
      actions: [
        HostDashboardMenuButton(
          onNote: _editNote,
          onEdit: _openEdit,
          onDetails: _openDetails,
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: KelolaError(
                  message: _error!,
                  sudoUser: host?.username,
                ),
              ),
            if (dash != null && dash.failedUnitCount > 0) ...[
              ServiceRow(
                risk: RiskLevel.read,
                status: HealthStatus.failed,
                name: '${dash.failedUnitCount} units failed',
                meta: dash.failedUnitNames.isEmpty
                    ? 'open services, failed first'
                    : dash.failedUnitNames.join(' · '),
                onTap: () => _openUnits(failedOnly: true),
              ),
              const SizedBox(height: 8),
            ] else if (dash != null && dash.diskRootPercent >= 90) ...[
              ServiceRow(
                risk: RiskLevel.read,
                status: HealthStatus.warning,
                name: '/ at ${dash.diskRootPercent}%',
                meta: 'open df, then du',
                onTap: () => _open((id) => DiskScreen(hostId: id)),
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
                        label: 'Load 1m',
                        value: dash.load1.toStringAsFixed(2),
                        meterFraction:
                            loadMeterFraction(dash.load1, facts?.nprocCores),
                        status: loadHealth(dash.load1, facts?.nprocCores),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        meterFraction: dash.memUsedPercent / 100,
                        status: _pctHealth(dash.memUsedPercent),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _open((id) => DiskScreen(hostId: id)),
                      child: StatCard(
                        label: 'Disk /',
                        value: '${dash.diskRootPercent}',
                        unit: '%',
                        meterFraction: dash.diskRootPercent / 100,
                        status: _pctHealth(dash.diskRootPercent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: StatCard(
                      label: 'Updates',
                      value: '—',
                      status: HealthStatus.unknown,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _open(
                  (id) => MetricsScreen(
                    hostId: id,
                    focus: MetricsFocus.cpu,
                  ),
                ),
                child: RiskBand(
                  risk: RiskLevel.read,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CPU',
                        style: KelolaType.mono(
                          color: c.dim,
                          size: 8.5,
                          letterSpacing: 0.9,
                        ),
                      ),
                      Text(
                        '${cpuNow.toStringAsFixed(0)}%',
                        style: KelolaType.display(color: c.text, size: 18),
                      ),
                      Sparkline(values: spark, color: c.amber),
                    ],
                  ),
                ),
              ),
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
                    label: 'Workloads',
                    meta: 'containers',
                    onTap: () => _open((id) => ContainersScreen(hostId: id)),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ToolTile(
                    label: 'Note',
                    meta: 'local',
                    onTap: _editNote,
                  ),
                ),
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
                name: 'Command',
                meta: 'no PTY · audited',
                onTap: () => openCommandSheet(context, ref, host),
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
              DashboardStatusLine(
                checkedAt: host.attentionAt,
                readOnly: host.readOnly,
                sudoNeedsPassword: host.sudoNeedsPassword,
                sudoUser: host.username,
              ),
            ],
          ],
        ),
      ),
    );
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
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Host note'),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Local only. Searchable. Not sent to the host.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Save'),
            ),
          ],
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDetailsScreen(
          host: host,
          facts: _facts ?? HostFacts.undiscovered,
        ),
      ),
    );
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
      final msg = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: HostActionProbe(verb),
        facts: _facts,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
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
  });

  final VoidCallback onNote;
  final VoidCallback onEdit;
  final VoidCallback onDetails;
  final VoidCallback onAudit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        switch (v) {
          case 'note':
            onNote();
          case 'edit':
            onEdit();
          case 'details':
            onDetails();
          case 'audit':
            onAudit();
          case 'delete':
            onRemove();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'note', child: Text('Note')),
        const PopupMenuItem(value: 'edit', child: Text('Edit host')),
        const PopupMenuItem(value: 'details', child: Text('Host details')),
        const PopupMenuItem(value: 'audit', child: Text('Audit log')),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Remove host',
            style: TextStyle(color: c.red),
          ),
        ),
      ],
    );
  }
}
