import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/bulk_restart.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;

enum _RowState { running, waiting, done, failed, skipped }

/// Deployment `redis` and StatefulSet `redis` can share a namespace.
String _key(K8sWorkload w) => '${w.kind.name}|${w.title}';

/// M32: `rollout restart` for several workloads in one namespace (Pro,
/// `snippetMulti`). Preview shows each command; one typed confirm for the
/// batch; then sequential restarts where one failure does not stop the rest.
class K8sBulkRestartScreen extends ConsumerStatefulWidget {
  const K8sBulkRestartScreen({
    super.key,
    required this.host,
    required this.facts,
    required this.workloads,
    this.initialNamespace = '',
  });

  final Host host;
  final HostFacts facts;
  final List<K8sWorkload> workloads;
  final String initialNamespace;

  @override
  ConsumerState<K8sBulkRestartScreen> createState() =>
      _K8sBulkRestartScreenState();
}

class _K8sBulkRestartScreenState extends ConsumerState<K8sBulkRestartScreen> {
  late final List<String> _namespaces;
  String _namespace = '';
  final Set<String> _checked = {};
  final Map<String, _RowState> _state = {};
  final Map<String, String> _result = {};
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _namespaces = bulkRestartNamespaces(widget.workloads);
    final start = _namespaces.contains(widget.initialNamespace)
        ? widget.initialNamespace
        : (_namespaces.isEmpty ? '' : _namespaces.first);
    _select(start);
  }

  List<K8sWorkload> get _candidates =>
      bulkRestartCandidates(widget.workloads, _namespace);

  void _select(String ns) {
    _namespace = ns;
    _checked
      ..clear()
      ..addAll([
        if (bulkRestartCheckedByDefault(ns))
          for (final w in bulkRestartCandidates(widget.workloads, ns)) _key(w),
      ]);
    _state.clear();
    _result.clear();
  }

  Future<void> _run() async {
    final targets = [
      for (final w in _candidates)
        if (_checked.contains(_key(w))) w,
    ];
    if (targets.isEmpty) {
      return;
    }
    var confirmed = false;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => KelolaSheet(
        child: DestructiveConfirmSheet(
          title: 'Restart ${targets.length} in $_namespace?',
          consequence: 'This rolls ${targets.length} workloads in '
              '$_namespace on ${widget.host.alias}. Each one must be ready '
              'again (up to 2 minutes) before the next starts; if one is '
              'not, the rest are skipped.',
          warning: 'Type $_namespace to confirm.',
          confirmToken: _namespace,
          onConfirmed: () => confirmed = true,
        ),
      ),
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _running = true;
      _result.clear();
      _state.clear();
    });
    var stopped = false;
    for (final w in targets) {
      if (!mounted) {
        return;
      }
      final key = _key(w);
      if (stopped) {
        _state[key] = _RowState.skipped;
        _result[key] = 'skipped: an earlier rollout was not ready';
        continue;
      }
      setState(() => _state[key] = _RowState.running);
      try {
        await runHostProbe(
          ref: ref,
          context: context,
          host: widget.host,
          probe: WorkloadActionProbe(workload: w, verb: WorkloadVerb.restart),
          facts: widget.facts,
        );
      } on ReadOnlyViolation {
        _state[key] = _RowState.failed;
        _result[key] = 'This host is read-only.';
        // Every later restart would be refused the same way.
        stopped = true;
        continue;
      } catch (e) {
        // The command itself failed (RBAC, not found): nothing rolled, so
        // the next workload is safe to try.
        if (mounted) {
          setState(() {
            _state[key] = _RowState.failed;
            _result[key] = describeSshError(e);
          });
        }
        continue;
      }
      if (!mounted) {
        return;
      }
      // `rollout restart` returns once the patch is applied. Wait for the
      // pods to be ready before rolling the next one, so single-replica
      // workloads in one namespace never go down together.
      setState(() => _state[key] = _RowState.waiting);
      try {
        await runHostProbe(
          ref: ref,
          context: context,
          host: widget.host,
          probe: WorkloadRolloutStatusProbe(workload: w),
          facts: widget.facts,
        );
        _state[key] = _RowState.done;
        _result[key] = 'restarted · ready';
      } catch (e) {
        _state[key] = _RowState.failed;
        _result[key] = 'restarted, not ready: ${e is RolloutNotReady ? e : describeSshError(e)}';
        stopped = true;
      }
      if (mounted) {
        setState(() {});
      }
    }
    if (mounted) {
      setState(() {});
    }
    if (mounted) {
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final rows = _candidates;
    final selected = rows.where((w) => _checked.contains(_key(w))).length;
    // Leaving mid-run would silently skip the rest of the batch.
    return PopScope(
      canPop: !_running,
      child: _scaffold(c, rows, selected),
    );
  }

  Widget _scaffold(KelolaColors c, List<K8sWorkload> rows, int selected) {
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: 'Restart namespace',
        contextLine: _namespace.isEmpty ? '' : _namespace,
      ),
      body: ListView(
        padding: kelolaScrollPadding(context),
        children: [
          if (_namespaces.isEmpty)
            const KelolaEmpty(
              body: 'No Deployments, StatefulSets or DaemonSets to restart.',
            )
          else ...[
            const SectionSlab('Namespace'),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final ns in _namespaces)
                  FilterPill(
                    label: ns,
                    selected: ns == _namespace,
                    onTap: _running ? null : () => setState(() => _select(ns)),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const SectionSlab('Workloads'),
            for (final w in rows) ...[
              _row(c, w),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),
            KelolaPrimaryButton(
              label: _running ? 'Restarting…' : 'Restart $selected',
              onTap: _running || selected == 0 ? null : _run,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(KelolaColors c, K8sWorkload w) {
    final key = _key(w);
    final state = _state[key];
    final result = _result[key];
    final checked = _checked.contains(key);
    final command = WorkloadActionProbe(
      workload: w,
      verb: WorkloadVerb.restart,
    ).command(widget.facts);
    return ServiceRow(
      risk: RiskLevel.mutate,
      status: switch (state) {
        _RowState.done => HealthStatus.healthy,
        _RowState.failed => HealthStatus.failed,
        _RowState.skipped => HealthStatus.warning,
        _ => null,
      },
      // Same select pattern as snippet multi-exec: tap toggles, meta says so.
      onTap: _running
          ? null
          : () => setState(() {
                if (!_checked.add(key)) {
                  _checked.remove(key);
                }
              }),
      name: '${w.kind.short} ${w.name}',
      meta: switch (state) {
        _RowState.running => 'restarting…',
        _RowState.waiting => 'waiting for ready…',
        _RowState.done || _RowState.failed || _RowState.skipped =>
          result ?? '',
        null => '${checked ? 'selected' : 'not selected'} · ${w.readyLabel}',
      },
      detail: command,
    );
  }
}
