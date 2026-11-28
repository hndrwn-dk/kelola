import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_filters.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/widgets/argo_resource_sheet.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;

/// Read-only detail of one Argo CD Application, from the read the home
/// already ran. Never opens its own SSH session and has no actions.
class ArgoAppDetailScreen extends ConsumerStatefulWidget {
  const ArgoAppDetailScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.app,
    required this.workloads,
    required this.readAt,
    this.now,
  });

  final Host host;
  final HostFacts facts;
  final ArgoApp app;
  final List<K8sWorkload> workloads;
  final DateTime readAt;
  final DateTime Function()? now;

  @override
  ConsumerState<ArgoAppDetailScreen> createState() =>
      _ArgoAppDetailScreenState();
}

class _ArgoAppDetailScreenState extends ConsumerState<ArgoAppDetailScreen> {
  ArgoResourceFilter _filter = ArgoResourceFilter.all;

  static const _workloadKinds = {
    K8sKind.deployment,
    K8sKind.statefulSet,
    K8sKind.daemonSet,
    K8sKind.pod,
  };

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final now = (widget.now ?? () => DateTime.now().toUtc())();
    final stale = now.difference(widget.readAt.toUtc()) > Host.attentionFreshFor;
    final age = stale ? k8sAge(widget.readAt.toUtc(), now.toUtc()) : '';
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.host.id),
        title: app.name,
        contextLine: age.isEmpty ? app.namespace : 'as of $age',
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          _band(app, now),
          for (var i = 0; i < app.sources.length; i++) _sourceGroup(app, i),
          FactGroup(
            heading: 'Destination',
            entries: [
              FactEntry(label: 'Server', value: _orDash(app.destServer)),
              FactEntry(label: 'Namespace', value: _orDash(app.destNamespace)),
            ],
          ),
          FactGroup(
            heading: 'Sync policy',
            entries: [FactEntry(label: 'Policy', value: _policy(app))],
          ),
          _operation(app, now),
          if (app.conditions.isNotEmpty)
            FactGroup(
              heading: 'Conditions',
              entries: [
                for (final c in app.conditions)
                  FactEntry(label: c.type, value: _orDash(c.message)),
              ],
            ),
          ..._resources(app),
          if (app.history.isNotEmpty) ..._history(app, now),
        ],
      ),
    );
  }

  Widget _band(ArgoApp app, DateTime now) {
    final c = context.kc;
    final findings = app.findings(now);
    final text = findings.isNotEmpty
        ? '${findings.first.subject}: ${findings.first.message}'
        : '${argoSyncLabel(app.sync)} · ${argoHealthLabel(app.health)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RiskBand.forHealth(
        status: app.status(now),
        child: Text(text, style: KelolaType.mono(color: c.text, size: 13)),
      ),
    );
  }

  Widget _sourceGroup(ArgoApp app, int i) {
    final s = app.sources[i];
    final synced = i < app.syncedRevisions.length
        ? shortArgoRevision(app.syncedRevisions[i])
        : '';
    final chart = s.chart;
    final path = s.path;
    return FactGroup(
      heading: app.sources.length > 1 ? 'Source ${i + 1}' : 'Source',
      entries: [
        FactEntry(label: 'Repository', value: _orDash(s.repoUrl)),
        if (chart != null && chart.isNotEmpty)
          FactEntry(label: 'Chart', value: chart),
        if (path != null && path.isNotEmpty)
          FactEntry(label: 'Path', value: path),
        FactEntry(label: 'Target revision', value: _orDash(s.targetRevision)),
        if (synced.isNotEmpty)
          FactEntry(label: 'Synced revision', value: synced),
      ],
    );
  }

  String _policy(ArgoApp app) {
    if (!app.automated) {
      return 'Manual';
    }
    return [
      'Automated',
      if (app.prune) 'prune',
      if (app.selfHeal) 'self-heal',
    ].join(' · ');
  }

  Widget _operation(ArgoApp app, DateTime now) {
    final msg = app.opMessage;
    return FactGroup(
      heading: 'Last operation',
      entries: [
        FactEntry(label: 'Phase', value: argoOpPhaseLabel(app.opPhase)),
        if (app.opStartedAt != null)
          FactEntry(label: 'Started', value: _stamp(app.opStartedAt!, now)),
        if (app.opFinishedAt != null)
          FactEntry(label: 'Finished', value: _stamp(app.opFinishedAt!, now)),
        if (msg != null && msg.isNotEmpty)
          FactEntry(label: 'Message', value: msg),
      ],
    );
  }

  List<Widget> _resources(ArgoApp app) {
    final all = app.resources;
    final shown = [
      for (final r in all)
        if (_filter.matches(r)) r,
    ];
    return [
      const SectionSlab('Resources'),
      Wrap(
        spacing: 5,
        runSpacing: 5,
        children: [
          for (final f in ArgoResourceFilter.values)
            FilterPill(
              key: ValueKey('argo-res-${f.name}'),
              label: '${f.label} ${f.count(all)}',
              selected: _filter == f,
              onTap: () => setState(() => _filter = f),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (shown.isEmpty)
        KelolaEmpty(body: _filter.emptyCopy)
      else
        K8sRows(
          rows: [
            for (final r in shown)
              K8sListRow(
                name: r.name,
                meta: [
                  r.kind,
                  if (r.namespace.isNotEmpty) r.namespace,
                  argoSyncLabel(r.sync),
                  argoHealthLabel(r.health),
                ].join(' · '),
                status: argoResourceStatus(r),
                onTap: () => _openResource(r),
              ),
          ],
        ),
    ];
  }

  List<Widget> _history(ArgoApp app, DateTime now) {
    return [
      const SectionSlab('History'),
      K8sRows(
        rows: [
          for (final h in app.history)
            K8sListRow(
              name: h.revision,
              meta: k8sAge(h.deployedAt?.toUtc(), now.toUtc()),
              status: HealthStatus.unknown,
            ),
        ],
      ),
    ];
  }

  K8sWorkload? _workloadFor(ArgoResource r) {
    final kind = parseK8sKind(r.kind);
    if (kind == null || !_workloadKinds.contains(kind)) {
      return null;
    }
    for (final w in widget.workloads) {
      if (w.kind == kind && w.namespace == r.namespace && w.name == r.name) {
        return w;
      }
    }
    return null;
  }

  void _openResource(ArgoResource r) {
    final w = _workloadFor(r);
    if (w == null) {
      showArgoResourceSheet(context, r);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WorkloadDetailScreen(
          host: widget.host,
          facts: widget.facts,
          workload: w,
        ),
      ),
    );
  }

  /// ISO time (UTC, whole seconds) and its age, for the mono values.
  String _stamp(DateTime at, DateTime now) {
    final iso =
        at.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
    final age = k8sAge(at.toUtc(), now.toUtc());
    return age.isEmpty ? iso : '$iso · $age ago';
  }

  String _orDash(String v) => v.isEmpty ? '-' : v;
}
