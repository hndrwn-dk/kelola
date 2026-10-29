import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class KubernetesHomeScreen extends ConsumerStatefulWidget {
  const KubernetesHomeScreen({
    super.key,
    required this.hostId,
    this.factsOverride,
  });

  final String hostId;

  /// Test seam. Production always loads facts from the host.
  final HostFacts? factsOverride;

  @override
  ConsumerState<KubernetesHomeScreen> createState() =>
      _KubernetesHomeScreenState();
}

class _KubernetesHomeScreenState extends ConsumerState<KubernetesHomeScreen> {
  Host? _host;
  HostFacts? _facts;
  ClusterHealth? _cluster;
  WorkloadInventory _inv = const WorkloadInventory(rows: []);
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final host = await ref.read(hostRepositoryProvider).get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      var facts = widget.factsOverride;
      if (facts == null) {
        facts = await ref.read(hostRepositoryProvider).facts(host.id) ??
            HostFacts.undiscovered;
        if (facts.runtimes.isEmpty) {
          if (!mounted) {
            return;
          }
          facts = await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            probe: const HostFactsProbe(),
          );
          await ref.read(hostRepositoryProvider).saveFacts(host.id, facts);
        }
      }
      if (!mounted) {
        return;
      }
      if (kubectlFlavor(facts) == KubectlFlavor.none) {
        setState(() {
          _host = host;
          _facts = facts;
          _cluster = const ClusterHealth(
            apiReachable: false,
            controlPlaneReady: 0,
            controlPlaneDesired: 0,
            missingKubectl: true,
          );
          _inv = const WorkloadInventory(rows: [], missingKubectl: true);
        });
        return;
      }

      final cluster = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const ClusterHealthProbe(),
        facts: facts,
      );
      if (!mounted) {
        return;
      }
      final inv = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const WorkloadListProbe(),
        facts: facts,
      );
      if (!mounted) {
        return;
      }
      final dns = coreDnsReadyFromWorkloads(inv.rows);
      setState(() {
        _host = host;
        _facts = facts;
        _cluster = cluster.withCoreDns(dns);
        _inv = inv;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  WorkloadHomeSummary get _summary => WorkloadHomeSummary.from(_inv.rows);

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final cluster = _cluster;
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: 'Kubernetes',
        contextLine: cluster == null
            ? ''
            : cluster.missingKubectl
                ? 'no kubectl'
                : _overallLabel(cluster.overall),
        actions: [
          KelolaChromeIconButton(
            tooltip: 'Refresh',
            icon: Icons.refresh_rounded,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              minHeight: 1.5,
              backgroundColor: c.surface,
              color: c.amber,
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(c),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(KelolaColors c) {
    final cluster = _cluster;
    if (cluster != null &&
        cluster.missingKubectl &&
        !_loading &&
        _error == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kelolaScrollPadding(context),
        children: const [KelolaEmpty(body: workloadEmptyCopy)],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kelolaScrollPadding(context),
      children: [
        if (_error != null) ...[
          KelolaError(message: _error!, sudoUser: _host?.username),
          const SizedBox(height: 12),
        ],
        if (cluster != null && !cluster.missingKubectl) ...[
          const SectionSlab('Cluster'),
          RiskBand.forHealth(
            status: cluster.overall,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metaRow(c, 'API server', cluster.apiReachable ? 'reachable' : 'unreachable'),
                const SizedBox(height: 6),
                _metaRow(c, 'Control plane', cluster.controlPlaneLabel),
                const SizedBox(height: 6),
                _metaRow(c, 'CoreDNS', _coreDnsLabel(cluster.coreDnsReady)),
                const SizedBox(height: 6),
                _metaRow(
                  c,
                  'This host',
                  cluster.thisHostMatched && cluster.thisHost != null
                      ? cluster.thisHost!.membershipLabel
                      : 'unmatched',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const SectionSlab('Workloads'),
          _workloadsBlock(c),
        ],
      ],
    );
  }

  Widget _workloadsBlock(KelolaColors c) {
    final summary = _summary;
    final host = _host;
    final facts = _facts;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line, width: 1),
        borderRadius: BorderRadius.circular(KelolaRadii.md),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              FilterPill(
                label: '${summary.deployments} deploy',
                selected: false,
                onTap: null,
              ),
              FilterPill(
                label: '${summary.statefulSets} sts',
                selected: false,
                onTap: null,
              ),
              FilterPill(
                label: '${summary.daemonSets} ds',
                selected: false,
                onTap: null,
              ),
              FilterPill(
                label: '${summary.pods} pods',
                selected: false,
                onTap: null,
              ),
              if (summary.notReadyCount > 0)
                FilterPill(
                  label: '${summary.notReadyCount} not ready',
                  selected: true,
                  onTap: null,
                ),
            ],
          ),
          if (summary.worst.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final row in summary.worst) ...[
              ServiceRow(
                risk: RiskLevel.read,
                status: row.health,
                name: row.title,
                meta: '${row.kind.short} · ${row.readyLabel}'
                    '${row.phase.isEmpty ? '' : ' · ${row.phase}'}',
                onTap: host == null || facts == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkloadDetailScreen(
                              host: host,
                              facts: facts,
                              workload: row,
                            ),
                          ),
                        );
                      },
              ),
              const SizedBox(height: 6),
            ],
          ] else ...[
            const SizedBox(height: 10),
            Text(
              'All listed workloads ready',
              style: KelolaType.body(color: c.muted, size: 13),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WorkloadsScreen(
                    hostId: widget.hostId,
                    factsOverride: widget.factsOverride ?? _facts,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: c.amber),
            child: Text(
              'All workloads',
              style: KelolaType.display(color: c.ink, size: 14, weight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(KelolaColors c, String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: KelolaType.body(color: c.muted, size: 12)),
        ),
        Text(value, style: KelolaType.mono(color: c.text, size: 12)),
      ],
    );
  }

  String _coreDnsLabel(bool? ready) {
    if (ready == null) {
      return 'unknown';
    }
    return ready ? 'running' : 'not ready';
  }

  String _overallLabel(HealthStatus status) {
    return switch (status) {
      HealthStatus.healthy => 'healthy',
      HealthStatus.warning => 'attention',
      HealthStatus.failed => 'failed',
      HealthStatus.unknown => 'unknown',
    };
  }
}
