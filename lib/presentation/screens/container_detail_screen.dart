import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/containers/container_detail.dart';
import 'package:kelola/domain/containers/container_lockout.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_inspect_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_container_action.dart';
import 'package:kelola/providers.dart';

const _actionOrder = [
  ContainerVerb.restart,
  ContainerVerb.stop,
  ContainerVerb.start,
  ContainerVerb.remove,
];

class ContainerDetailScreen extends ConsumerStatefulWidget {
  const ContainerDetailScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.row,
  });

  final Host host;
  final HostFacts facts;
  final ContainerRow row;

  @override
  ConsumerState<ContainerDetailScreen> createState() =>
      _ContainerDetailScreenState();
}

class _ContainerDetailScreenState extends ConsumerState<ContainerDetailScreen> {
  ContainerDetail? _detail;
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
        probe: ContainerInspectProbe(widget.row),
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

  Future<void> _act(ContainerVerb verb) async {
    final allowed = await confirmContainerAction(
      context,
      hostAlias: widget.host.alias,
      row: widget.row,
      verb: verb,
      sshPort: widget.host.port,
    );
    if (!allowed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: ContainerActionProbe(
          row: widget.row,
          verb: verb,
          sshPort: widget.host.port,
        ),
        facts: widget.facts,
      );
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
    final row = widget.row;

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
              row.title,
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              row.image.isEmpty ? row.id : row.image,
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
                  const SectionSlab('Actions'),
                  const SizedBox(height: 6),
                  for (final verb in _actionOrder)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ServiceRow(
                        risk: containerActionRisk(
                          verb,
                          row,
                          sshPort: widget.host.port,
                        ),
                        name:
                            '${verb.name[0].toUpperCase()}${verb.name.substring(1)}',
                        meta: _actionMeta(verb),
                        onTap: _busy ? null : () => _act(verb),
                      ),
                    ),
                  if (detail != null) ...[
                    if (detail.env.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const SectionSlab('Env'),
                      const SizedBox(height: 6),
                      RiskBand(
                        risk: RiskLevel.read,
                        child: SelectableText(
                          detail.env.join('\n'),
                          style: KelolaType.mono(color: c.muted, size: 10.5),
                        ),
                      ),
                    ],
                    if (detail.mounts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FactGroup(
                        heading: 'Mounts',
                        entries: [
                          for (final m in detail.mounts)
                            FactEntry(label: 'Mount', value: m),
                        ],
                      ),
                    ],
                    if (detail.networks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      FactGroup(
                        heading: 'Networks',
                        entries: [
                          for (final n in detail.networks)
                            FactEntry(label: 'Network', value: n),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    FactGroup(
                      heading: 'Resources',
                      entries: [
                        if (detail.cpuPerc.isNotEmpty)
                          FactEntry(label: 'CPU', value: detail.cpuPerc),
                        if (detail.memUsage.isNotEmpty)
                          FactEntry(label: 'Memory', value: detail.memUsage),
                        if (detail.restartPolicy.isNotEmpty)
                          FactEntry(
                            label: 'Restart',
                            value: detail.restartPolicy,
                          ),
                        if (row.publishedPorts.isNotEmpty)
                          FactEntry(
                            label: 'Ports',
                            value: row.publishedPorts,
                          ),
                        FactEntry(label: 'Id', value: row.id),
                      ],
                    ),
                    if (detail.logs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const SectionSlab('Logs'),
                      const SizedBox(height: 6),
                      RiskBand(
                        risk: RiskLevel.read,
                        child: SelectableText(
                          detail.logs,
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

  String _actionMeta(ContainerVerb verb) {
    if (isLockoutContainerAction(verb.name, widget.row,
        sshPort: widget.host.port)) {
      return 'destructive · will end this session';
    }
    if (verb == ContainerVerb.remove) {
      return 'destructive · type ${widget.row.title}';
    }
    return 'mutate · one confirmation';
  }
}
