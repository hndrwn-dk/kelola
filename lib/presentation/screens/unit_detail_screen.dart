import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/probes/unit_detail_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/unit_detail_view.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/journal_screen.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';
import 'package:kelola/providers.dart';

const _actionOrder = [
  UnitVerb.restart,
  UnitVerb.reload,
  UnitVerb.disable,
  UnitVerb.stop,
  UnitVerb.start,
  UnitVerb.enable,
];

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
      } else if (result.mismatch) {
        setState(() {
          _error =
              '${verb.name} returned 0, but ${widget.unitName} is still ${result.activeState} (${result.subState}). A k3s/nginx pod can keep serving after the systemd unit stops.';
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
    final c = context.kc;
    final detail = _detail;
    final kicker = detail == null ? null : unitDetailKicker(detail);
    final journalTip = widget.facts.hasJournald && !widget.facts.journalReadable;

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.unitName,
              style: KelolaType.display(color: c.text, size: 16),
            ),
            if (kicker != null)
              Text(
                kicker,
                style: KelolaType.mono(
                  color: c.dim,
                  size: 8.5,
                  letterSpacing: 0.9,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                children: [
                  if (_error != null) ...[
                    KelolaError(
                      message: _error!,
                      sudoUser: widget.host.username,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (detail != null) ...[
                    if (detail.activeState == 'failed') ...[
                      RiskBand(
                        risk: RiskLevel.read,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Result',
                              style: KelolaType.mono(
                                color: c.dim,
                                size: 8.5,
                                letterSpacing: 0.9,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              unitResultBody(detail),
                              style: KelolaType.mono(
                                color: c.forHealth(HealthStatus.failed),
                                size: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _slab(c, 'Actions'),
                    const SizedBox(height: 6),
                    for (final verb in _actionOrder)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ServiceRow(
                          risk: unitActionRisk(verb, widget.unitName),
                          name: '${verb.name[0].toUpperCase()}${verb.name.substring(1)}',
                          meta: unitActionMeta(verb, widget.unitName),
                          onTap: _busy ? null : () => _act(verb),
                        ),
                      ),
                    const SizedBox(height: 8),
                    _slab(c, 'Recent log'),
                    const SizedBox(height: 6),
                    RiskBand(
                      risk: RiskLevel.read,
                      child: SelectableText(
                        detail.logs.isEmpty
                            ? '(no journal output)'
                            : detail.logs,
                        style: KelolaType.mono(
                          color: c.muted,
                          size: 10.5,
                        ),
                      ),
                    ),
                    if (journalTip) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Journal is not readable for this user.',
                        style: KelolaType.body(color: c.muted, size: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ServiceRow(
                      risk: RiskLevel.read,
                      name: 'Journal',
                      meta: 'read · full unit log',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => JournalScreen(
                              hostId: widget.host.id,
                              unit: widget.unitName,
                            ),
                          ),
                        );
                      },
                    ),
                    if (detail.dependencies.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _slab(c, 'Dependencies'),
                      const SizedBox(height: 6),
                      RiskBand(
                        risk: RiskLevel.read,
                        child: SelectableText(
                          detail.dependencies,
                          style: KelolaType.mono(color: c.muted, size: 10.5),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slab(KelolaColors c, String label) {
    return Text(
      label.toUpperCase(),
      style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
    );
  }
}
