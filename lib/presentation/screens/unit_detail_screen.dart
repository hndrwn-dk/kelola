import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/probes/unit_detail_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';
import 'package:kelola/presentation/widgets/risk_band.dart';
import 'package:kelola/providers.dart';

class UnitDetailScreen extends ConsumerStatefulWidget {
  const UnitDetailScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.unitName,
  });

  final Host host;
  final HostFacts facts;
  final String unitName;

  @override
  ConsumerState<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends ConsumerState<UnitDetailScreen> {
  UnitDetail? _detail;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final detail = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: UnitDetailProbe(widget.unitName),
        facts: widget.facts,
      );
      setState(() => _detail = detail);
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _act(UnitVerb verb) async {
    final allowed = await confirmUnitAction(
      context,
      hostAlias: widget.host.alias,
      unit: widget.unitName,
      verb: verb,
    );
    if (!allowed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: UnitActionProbe(unitName: widget.unitName, verb: verb),
        facts: widget.facts,
      );
      if (!result.ok) {
        setState(() {
          _error = result.stderr.isEmpty
              ? '${verb.name} exited ${result.exitCode}'
              : result.stderr;
        });
      }
      await _load();
    } on ReadOnlyViolation {
      setState(() => _error = 'This host is read-only.');
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final detail = _detail;
    final journalTip = widget.facts.hasJournald && !widget.facts.journalReadable;

    return Scaffold(
      appBar: AppBar(title: Text(widget.unitName)),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: colors.red)),
            const SizedBox(height: 12),
          ],
          if (detail != null) ...[
            RiskBand(
              level: detail.activeState == 'failed'
                  ? RiskLevel.destructive
                  : RiskLevel.read,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.description.isEmpty
                        ? widget.unitName
                        : detail.description,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      detail.activeState,
                      detail.subState,
                      if (detail.unitFileState.isNotEmpty) detail.unitFileState,
                      if (detail.mainPid.isNotEmpty && detail.mainPid != '0')
                        'pid ${detail.mainPid}',
                    ].join(' · '),
                    style: TextStyle(color: colors.dim, fontSize: 12),
                  ),
                  if (detail.fragmentPath.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail.fragmentPath,
                      style: TextStyle(color: colors.dim, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final verb in UnitVerb.values)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _act(verb),
                    child: Text(verb.name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Logs', style: TextStyle(color: colors.dim, fontSize: 11)),
            const SizedBox(height: 6),
            SelectableText(
              detail.logs.isEmpty ? '(no journal output)' : detail.logs,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: colors.muted,
              ),
            ),
            if (journalTip) ...[
              const SizedBox(height: 8),
              Text(
                'sudo usermod -aG systemd-journal ${widget.host.username}',
                style: TextStyle(color: colors.dim, fontSize: 12),
              ),
            ],
            if (detail.dependencies.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Dependencies',
                style: TextStyle(color: colors.dim, fontSize: 11),
              ),
              const SizedBox(height: 6),
              SelectableText(
                detail.dependencies,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: colors.muted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
