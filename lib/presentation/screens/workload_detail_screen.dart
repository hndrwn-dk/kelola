import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_actions.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/probes/workload_logs_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/probes/workload_yaml_probe.dart';
import 'package:kelola/presentation/screens/workload_yaml_screen.dart';
import 'package:kelola/presentation/destructive_auth.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/workload_exec_sheet.dart';
import 'package:kelola/presentation/widgets/confirm_workload_action.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class WorkloadDetailScreen extends ConsumerStatefulWidget {
  const WorkloadDetailScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.workload,
  });

  final Host host;
  final HostFacts facts;
  final K8sWorkload workload;

  @override
  ConsumerState<WorkloadDetailScreen> createState() =>
      _WorkloadDetailScreenState();
}

class _WorkloadDetailScreenState extends ConsumerState<WorkloadDetailScreen> {
  late K8sWorkload _row;
  String _describe = '';
  List<K8sEvent> _events = const [];
  List<K8sTopRow> _top = const [];
  String _logs = '';
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _row = widget.workload;
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
      final row = _row;
      String describe = '';
      var events = const <K8sEvent>[];
      var top = const <K8sTopRow>[];
      String? error;

      try {
        describe = await runHostProbe(
          ref: ref,
          context: context,
          host: widget.host,
          probe: WorkloadDescribeProbe(
            kind: row.kind,
            namespace: row.namespace,
            name: row.name,
          ),
          facts: widget.facts,
        );
      } catch (e) {
        error = describeSshError(e);
      }
      if (!mounted) {
        return;
      }

      try {
        events = await runHostProbe(
          ref: ref,
          context: context,
          host: widget.host,
          probe: WorkloadEventsProbe(
            namespace: row.namespace,
            name: row.name,
          ),
          facts: widget.facts,
        );
      } catch (e) {
        error ??= describeSshError(e);
      }
      if (!mounted) {
        return;
      }

      try {
        top = await runHostProbe(
          ref: ref,
          context: context,
          host: widget.host,
          probe: WorkloadTopProbe(
            namespace: row.namespace,
            pod: row.kind == K8sKind.pod ? row.name : null,
          ),
          facts: widget.facts,
        );
      } catch (_) {
        // metrics-server is optional; describe and events still stand.
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _describe = describe;
        _events = events;
        _top = top;
        _error = error;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _logsTap() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final logs = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadLogsProbe(_row),
        facts: widget.facts,
      );
      if (!mounted) {
        return;
      }
      setState(() => _logs = logs);
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openYaml() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final yaml = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadYamlGetProbe(workload: _row),
        facts: widget.facts,
      );
      if (!mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WorkloadYamlScreen(
            host: widget.host,
            facts: widget.facts,
            workload: _row,
            initialYaml: yaml,
          ),
        ),
      );
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

  Future<void> _act(WorkloadVerb verb, {int? replicas}) async {
    final allowed = await confirmWorkloadAction(
      context,
      hostAlias: widget.host.alias,
      workload: _row,
      verb: verb,
      replicas: replicas,
    );
    if (!allowed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await requireDestructivePresence(
        ref.read(hardwareSignerProvider),
        risk: workloadActionRisk(verb),
        reason: '${verb.name} ${_row.title}',
      );
      if (!mounted) {
        return;
      }
      await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: WorkloadActionProbe(
          workload: _row,
          verb: verb,
          replicas: replicas,
        ),
        facts: widget.facts,
      );
      if (verb == WorkloadVerb.delete) {
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      if (verb == WorkloadVerb.scale && replicas != null) {
        _row = _row.copyWith(desired: replicas);
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
    final row = _row;
    return Scaffold(
      backgroundColor: c.ink,
      appBar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: row.title,
        contextLine: '${row.kind.short} · ${row.readyLabel}'
            '${row.phase.isEmpty ? '' : ' · ${row.phase}'}',
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
                physics: const AlwaysScrollableScrollPhysics(),
                padding: kelolaScrollPadding(context),
                children: [
                  if (_error != null) ...[
                    KelolaError(
                      message: _error!,
                      sudoUser: widget.host.username,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_describe.isNotEmpty) ...[
                    const SectionSlab('Describe'),
                    const SizedBox(height: 6),
                    RiskBand(
                      risk: RiskLevel.read,
                      child: SelectableText(
                        _describe,
                        style: KelolaType.mono(color: c.muted, size: 10.5),
                      ),
                    ),
                  ] else if (!_busy && _error == null)
                    const KelolaEmpty(
                      body: 'No describe output. Pull to refresh.',
                    ),
                  if (_events.isNotEmpty) ...[
                    const SectionSlab('Events'),
                    const SizedBox(height: 6),
                    for (final ev in _events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ServiceRow(
                          risk: RiskLevel.read,
                          status: ev.type.toLowerCase() == 'warning'
                              ? HealthStatus.warning
                              : HealthStatus.healthy,
                          name: ev.reason.isEmpty ? ev.type : ev.reason,
                          meta: ev.message,
                          kicker: ev.when.isEmpty ? ev.type : ev.when,
                        ),
                      ),
                  ],
                  if (_top.isNotEmpty) ...[
                    const SectionSlab('Top'),
                    const SizedBox(height: 6),
                    for (final t in _top)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ServiceRow(
                          risk: RiskLevel.read,
                          name: t.name,
                          meta: '${t.cpu} · ${t.memory}',
                        ),
                      ),
                  ],
                  if (_logs.isNotEmpty) ...[
                    const SectionSlab('Logs'),
                    const SizedBox(height: 6),
                    RiskBand(
                      risk: RiskLevel.read,
                      child: SelectableText(
                        _logs,
                        style: KelolaType.mono(color: c.muted, size: 10.5),
                      ),
                    ),
                  ],
                  const SectionSlab('Actions'),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.read,
                      name: 'YAML',
                      meta: 'read · then guarded apply',
                      onTap: _busy ? null : _openYaml,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ServiceRow(
                      risk: RiskLevel.read,
                      name: 'Logs',
                      meta: 'read · last 80 lines',
                      onTap: _busy ? null : _logsTap,
                    ),
                  ),
                  if (workloadCanExec(row.kind))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: RiskLevel.mutate,
                        name: 'Exec',
                        meta: 'mutate · one-shot, no PTY',
                        onTap: _busy
                            ? null
                            : () => openWorkloadExecSheet(
                                  context,
                                  host: widget.host,
                                  facts: widget.facts,
                                  workload: row,
                                ),
                      ),
                    ),
                  if (workloadCanRestart(row.kind))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: RiskLevel.mutate,
                        name: 'Restart',
                        meta: 'mutate · rollout restart',
                        onTap: _busy
                            ? null
                            : () => _act(WorkloadVerb.restart),
                      ),
                    ),
                  if (workloadCanScale(row.kind)) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: RiskLevel.mutate,
                        name: 'Scale up',
                        meta: 'mutate · ${row.desired} to ${nextScaleUp(row.desired)}',
                        onTap: _busy
                            ? null
                            : () => _act(
                                  WorkloadVerb.scale,
                                  replicas: nextScaleUp(row.desired),
                                ),
                      ),
                    ),
                    if (row.desired > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ServiceRow(
                          risk: RiskLevel.mutate,
                          name: 'Scale down',
                          meta:
                              'mutate · ${row.desired} to ${nextScaleDown(row.desired)}',
                          onTap: _busy
                              ? null
                              : () => _act(
                                    WorkloadVerb.scale,
                                    replicas: nextScaleDown(row.desired),
                                  ),
                        ),
                      ),
                  ],
                  if (workloadCanDelete(row.kind))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: RiskLevel.destructive,
                        name: 'Delete',
                        meta: 'destructive · type ${row.title}',
                        onTap: _busy
                            ? null
                            : () => _act(WorkloadVerb.delete),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
