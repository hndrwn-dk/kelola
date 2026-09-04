import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/fleet/fleet_actions.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/metrics_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/disk_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/packages_screen.dart';
import 'package:kelola/presentation/screens/containers_screen.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';
import 'package:kelola/providers.dart';

Future<void> openFleetHostSheet(
  BuildContext context,
  WidgetRef ref, {
  required Host host,
  required FleetHostHealth health,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => FleetHostSheet(host: host, health: health),
  );
}

class FleetHostSheet extends ConsumerStatefulWidget {
  const FleetHostSheet({
    super.key,
    required this.host,
    required this.health,
  });

  final Host host;
  final FleetHostHealth health;

  @override
  ConsumerState<FleetHostSheet> createState() => _FleetHostSheetState();
}

class _FleetHostSheetState extends ConsumerState<FleetHostSheet> {
  MetricsSnapshot? _metrics;
  String? _error;
  bool _loadingMetrics = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final snap = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: const MetricsProbe(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _metrics = snap;
        _loadingMetrics = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = describeSshError(e);
        _loadingMetrics = false;
      });
    }
  }

  Future<void> _runAction(FleetIssue issue) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      switch (issue.kind) {
        case FleetIssueKind.failedUnit:
          final names = await ref
              .read(hostRepositoryProvider)
              .listFailedUnitNames(widget.host.id);
          if (!mounted) {
            return;
          }
          final unit = names.isNotEmpty ? names.first : null;
          if (unit == null) {
            return;
          }
          final ok = await confirmUnitAction(
            context,
            hostAlias: widget.host.alias,
            unit: unit,
            verb: UnitVerb.restart,
          );
          if (!ok || !mounted) {
            return;
          }
          await runHostProbe(
            ref: ref,
            context: context,
            host: widget.host,
            probe: UnitActionProbe(unitName: unit, verb: UnitVerb.restart),
          );
        case FleetIssueKind.badContainer:
          if (!mounted) {
            return;
          }
          Navigator.of(context).pop();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ContainersScreen(hostId: widget.host.id),
            ),
          );
        case FleetIssueKind.diskCritical:
          if (!mounted) {
            return;
          }
          Navigator.of(context).pop();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DiskScreen(hostId: widget.host.id),
            ),
          );
        case FleetIssueKind.securityUpdates:
          if (!mounted) {
            return;
          }
          Navigator.of(context).pop();
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PackagesScreen(hostId: widget.host.id),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openHost() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDashboardScreen(hostId: widget.host.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final health = widget.health;
    final issues = fleetIssues(health);
    final actions = fleetQuickActions(health);
    final more = fleetMoreIssuesLabel(health);
    final metrics = _metrics;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(KelolaRadii.lg),
          ),
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Fleet', style: KelolaType.display(color: c.text, size: 16)),
            Text(
              widget.host.alias,
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
            const SizedBox(height: 12),
            if (_error != null) ...[
              KelolaError(message: _error!, sudoUser: widget.host.username),
              const SizedBox(height: 10),
            ],
            Text(
              'ISSUES',
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
            const SizedBox(height: 6),
            if (issues.isEmpty)
              Text(
                health.reachable ? 'No critical issues.' : 'Host unreachable.',
                style: KelolaType.body(color: c.muted, size: 13),
              )
            else
              for (final issue in issues) ...[
                ServiceRow(
                  risk: issue.kind == FleetIssueKind.failedUnit
                      ? RiskLevel.mutate
                      : RiskLevel.read,
                  name: issue.label,
                  meta: issue.meta,
                ),
                const SizedBox(height: 6),
              ],
            if (more != null) ...[
              Text(more, style: KelolaType.body(color: c.amber, size: 12)),
              const SizedBox(height: 8),
            ],
            Text(
              'LIVE',
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
            const SizedBox(height: 6),
            if (_loadingMetrics)
              Text('Sampling CPU…', style: KelolaType.mono(color: c.muted, size: 11))
            else if (metrics != null) ...[
              ServiceRow(
                risk: RiskLevel.read,
                name: 'CPU ${metrics.cpuPercent.toStringAsFixed(0)}%',
                meta:
                    'load ${metrics.load1.toStringAsFixed(2)} · mem ${metrics.memUsedPercent}%',
              ),
              const SizedBox(height: 6),
              Text(
                'TOP CPU',
                style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              for (final p in metrics.topCpu.take(3))
                Text(
                  '${p.cpu.toStringAsFixed(1)}%  ${p.command}  ${p.pid}',
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
              const SizedBox(height: 8),
              Text(
                'TOP MEM',
                style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              for (final p in metrics.topMem.take(3))
                Text(
                  '${p.mem.toStringAsFixed(1)}%  ${p.command}  ${p.pid}',
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
            ],
            const SizedBox(height: 14),
            for (final action in actions) ...[
              ServiceRow(
                risk: action.kind == FleetIssueKind.failedUnit
                    ? RiskLevel.mutate
                    : RiskLevel.read,
                name: action.label,
                meta: action.meta,
                onTap: _busy ? null : () => _runAction(action),
              ),
              const SizedBox(height: 6),
            ],
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Open host',
              meta: 'full dashboard',
              onTap: _openHost,
            ),
          ],
        ),
      ),
    );
  }
}
