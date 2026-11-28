import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_filters.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;

/// Read-only list of Argo CD Applications from the read the home already
/// ran. State pills and project pills combine (AND). Never opens its own
/// SSH session.
class ArgoAppsScreen extends ConsumerStatefulWidget {
  const ArgoAppsScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.apps,
    required this.workloads,
    required this.readAt,
    this.now,
    this.onOpenApp,
  });

  final Host host;
  final HostFacts facts;
  final ArgoApps apps;
  final List<K8sWorkload> workloads;
  final DateTime readAt;
  final DateTime Function()? now;

  /// Row tap. Null leaves the rows inert.
  final void Function(BuildContext context, ArgoApp app)? onOpenApp;

  @override
  ConsumerState<ArgoAppsScreen> createState() => _ArgoAppsScreenState();
}

class _ArgoAppsScreenState extends ConsumerState<ArgoAppsScreen> {
  ArgoAppFilter _filter = ArgoAppFilter.all;
  String? _project;

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? () => DateTime.now().toUtc())();
    final all = widget.apps.apps;
    final projects = argoProjectCounts(all);
    final names = projects.keys.toList()..sort();
    final project = names.length > 1 && projects.containsKey(_project)
        ? _project
        : null;
    final scoped = [
      for (final a in all)
        if (project == null || a.project == project) a,
    ];
    final shown = [
      for (final a in scoped)
        if (_filter.matches(a)) a,
    ];
    final entries = [
      for (final a in shown) (app: a, status: a.status(now)),
    ]..sort((x, y) {
        final byHealth = worstHealthFirst(x.status, y.status);
        return byHealth != 0 ? byHealth : x.app.name.compareTo(y.app.name);
      });

    final stale = now.difference(widget.readAt.toUtc()) > Host.attentionFreshFor;
    final age = stale ? k8sAge(widget.readAt.toUtc(), now.toUtc()) : '';
    final onOpen = widget.onOpenApp;

    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.host.id),
        title: 'Applications',
        contextLine: age.isEmpty ? '${all.length} total' : 'as of $age',
      ),
      body: ListView.builder(
        padding: kelolaScrollPadding(context),
        itemCount: entries.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return _header(names, projects, scoped, shown.isEmpty);
          }
          final e = entries[i - 1];
          return K8sRows(
            rows: [
              K8sListRow(
                name: e.app.name,
                meta: e.app.rowMeta,
                status: e.status,
                onTap: onOpen == null ? null : () => onOpen(context, e.app),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    List<String> names,
    Map<String, int> projects,
    List<ArgoApp> scoped,
    bool empty,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (final f in ArgoAppFilter.values)
              FilterPill(
                key: ValueKey('argo-filter-${f.name}'),
                label: '${f.label} ${f.count(scoped)}',
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
          ],
        ),
        if (names.length > 1) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final p in names)
                FilterPill(
                  key: ValueKey('argo-project-$p'),
                  label: 'Project $p ${projects[p]}',
                  selected: _project == p,
                  onTap: () => setState(() => _project = _project == p ? null : p),
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (empty) KelolaEmpty(body: _filter.emptyCopy),
      ],
    );
  }
}
