import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
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
  String _describe = '';
  List<K8sEvent> _events = const [];
  List<K8sTopRow> _top = const [];
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
      final row = widget.workload;
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

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final row = widget.workload;
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
