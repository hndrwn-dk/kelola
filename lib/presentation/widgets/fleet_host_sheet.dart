import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
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
  void Function(FleetHostHealth updated)? onHealthUpdated,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => KelolaSheet(
      child: FleetHostSheet(
        host: host,
        health: health,
        onHealthUpdated: onHealthUpdated,
      ),
    ),
  );
}

class FleetHostSheet extends ConsumerStatefulWidget {
  const FleetHostSheet({
    super.key,
    required this.host,
    required this.health,
    this.onHealthUpdated,
  });

  final Host host;
  final FleetHostHealth health;
  final void Function(FleetHostHealth updated)? onHealthUpdated;

  @override
  ConsumerState<FleetHostSheet> createState() => _FleetHostSheetState();
}

class _FleetHostSheetState extends ConsumerState<FleetHostSheet> {
  late FleetHostHealth _health;
  MetricsSnapshot? _metrics;
  String? _error;
  bool _loadingMetrics = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _health = widget.health;
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
      final updated = applyFleetMetricsSample(
        _health,
        load1: snap.load1,
        memPercent: snap.memUsedPercent,
      );
      // Sync write-back into the fleet grid before painting LIVE.
      widget.onHealthUpdated?.call(updated);
      if (!mounted) {
        return;
      }
      setState(() {
        _metrics = snap;
        _health = updated;
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
        case FleetIssueKind.unreachable:
        case FleetIssueKind.loadHigh:
        case FleetIssueKind.memHigh:
        case FleetIssueKind.pendingUpdates:
        case FleetIssueKind.rebootRequired:
          break;
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

  HealthStatus _issueStatus(FleetIssueKind kind) {
    return switch (kind) {
      FleetIssueKind.unreachable ||
      FleetIssueKind.failedUnit ||
      FleetIssueKind.badContainer ||
      FleetIssueKind.loadHigh =>
        HealthStatus.failed,
      FleetIssueKind.diskCritical ||
      FleetIssueKind.memHigh ||
      FleetIssueKind.securityUpdates ||
      FleetIssueKind.pendingUpdates ||
      FleetIssueKind.rebootRequired =>
        HealthStatus.warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final assessment = assessFleetHost(_health);
    final issues = assessment.issues;
    final metrics = _metrics;
    final live = fleetLiveStrings(_health);
    final loadText = live.load;
    final age = live.age.isEmpty ? 'just now' : live.age;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
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
          if (assessment.isHealthy)
            Text(
              'No critical issues.',
              style: KelolaType.body(color: c.muted, size: 13),
            )
          else
            for (final issue in issues) ...[
              ServiceRow(
                risk: issue.kind == FleetIssueKind.failedUnit
                    ? RiskLevel.mutate
                    : RiskLevel.read,
                status: _issueStatus(issue.kind),
                name: issue.label,
                meta: issue.meta,
                onTap: !issue.isActionable || _busy
                    ? null
                    : () => _runAction(issue),
              ),
              const SizedBox(height: 6),
            ],
          Text(
            'LIVE · $age',
            style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
          ),
          const SizedBox(height: 6),
          if (_loadingMetrics)
            Text(
              'Sampling CPU…',
              style: KelolaType.mono(color: c.muted, size: 11),
            )
          else ...[
            ServiceRow(
              risk: RiskLevel.read,
              name: metrics == null
                  ? 'load $loadText'
                  : 'CPU ${metrics.cpuPercent.toStringAsFixed(0)}%',
              meta: metrics == null
                  ? 'mem ${_health.memPercent}% · $age'
                  : 'load $loadText · mem ${_health.memPercent}% · $age',
            ),
            if (metrics != null) ...[
              const SizedBox(height: 6),
              Text(
                'TOP CPU',
                style:
                    KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
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
                style:
                    KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
              ),
              const SizedBox(height: 4),
              for (final p in metrics.topMem.take(3))
                Text(
                  '${p.mem.toStringAsFixed(1)}%  ${p.command}  ${p.pid}',
                  style: KelolaType.mono(color: c.text, size: 11),
                ),
            ],
          ],
          const SizedBox(height: 14),
          ServiceRow(
            risk: RiskLevel.read,
            name: 'Open host',
            meta: 'full dashboard',
            onTap: _openHost,
          ),
        ],
      ),
    );
  }
}
