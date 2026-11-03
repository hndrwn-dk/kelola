import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/k8s_resource_detail_screen.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class KubernetesHomeScreen extends ConsumerStatefulWidget {
  const KubernetesHomeScreen({
    super.key,
    required this.hostId,
    this.factsOverride,
    this.now,
  });

  final String hostId;

  /// Test seam. Production always loads facts from the host.
  final HostFacts? factsOverride;

  /// Test seam for event ages. Production uses the wall clock.
  final DateTime Function()? now;

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

  // Wave 2. Each section loads on its own: a value, or an error string
  // (RBAC denied, API down) shown only in that section.
  List<K8sClusterEvent>? _events;
  _SectionError? _eventsError;
  K8sNetworking? _net;
  _SectionError? _netError;
  K8sStorage? _storage;
  _SectionError? _storageError;

  /// When the sections were read; detail screens show "as of 3m ago".
  DateTime? _readAt;

  // Wave 3.
  K8sConfigInventory? _config;
  _SectionError? _configError;
  K8sSecurityInventory? _security;
  _SectionError? _securityError;

  // Wave 4.
  List<K8sRevision>? _changes;
  _SectionError? _changesError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// True while a load runs. Pull-to-refresh during a load must not start
  /// a second batch: that doubles the cluster-wide reads on the API server
  /// and can exceed sshd's MaxSessions (10) on the pooled connection.
  bool _inFlight = false;

  Future<void> _load() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
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
      // Host key is pinned by now, so these can share the pooled client.
      final results = await Future.wait([
        _section(host, facts, const ClusterEventsProbe()),
        _section(host, facts, const ServiceListProbe()),
        _section(host, facts, const StorageListProbe()),
        _section(host, facts, const ConfigInventoryProbe()),
        _section(host, facts, const SecurityInventoryProbe()),
        _section(host, facts, const RolloutHistoryProbe()),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _readAt = _now();
        _events = results[0].value as List<K8sClusterEvent>?;
        _eventsError = results[0].error;
        _net = results[1].value as K8sNetworking?;
        _netError = results[1].error;
        _storage = results[2].value as K8sStorage?;
        _storageError = results[2].error;
        _config = results[3].value as K8sConfigInventory?;
        _configError = results[3].error;
        _security = results[4].value as K8sSecurityInventory?;
        _securityError = results[4].error;
        _changes = results[5].value as List<K8sRevision>?;
        _changesError = results[5].error;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      _inFlight = false;
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<({Object? value, _SectionError? error})> _section<T>(
    Host host,
    HostFacts facts,
    Probe<T> probe,
  ) async {
    try {
      final value = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: probe,
        facts: facts,
      );
      return (value: value, error: null);
    } on K8sReadException catch (e) {
      return (
        value: null,
        error: _SectionError(e.toString(), fromServer: true),
      );
    } catch (e) {
      return (
        value: null,
        error: _SectionError(describeSshError(e), fromServer: false),
      );
    }
  }

  DateTime _now() => widget.now?.call() ?? DateTime.now().toUtc();

  WorkloadHomeSummary get _summary => WorkloadHomeSummary.from(_inv.rows);

  K8sSnapshot get _snapshot => K8sSnapshot(
        hostId: widget.hostId,
        host: _host,
        facts: _facts,
        workloads: _inv.rows,
        storage: _storage,
        readAt: _readAt,
        now: _now,
      );

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

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
            child: FactGroup(
              heading: null,
              framed: false,
              entries: [
                FactEntry(
                  label: 'API server',
                  value: cluster.apiReachable ? 'reachable' : 'unreachable',
                ),
                FactEntry(label: 'Control plane', value: cluster.controlPlaneLabel),
                FactEntry(label: 'Nodes', value: cluster.nodesLabel),
                if (cluster.notReadyNodes.isNotEmpty)
                  FactEntry(label: 'Not ready', value: _cap(cluster.notReadyNodes)),
                if (cluster.nodesTotal > 0)
                  FactEntry(
                    label: 'Pressure',
                    value: cluster.pressuredNodes.isEmpty
                        ? 'none'
                        : _cap(cluster.pressuredNodes),
                  ),
                FactEntry(label: 'CoreDNS', value: _coreDnsLabel(cluster.coreDnsReady)),
                FactEntry(
                  label: 'This host',
                  value: cluster.thisHostMatched && cluster.thisHost != null
                      ? cluster.thisHost!.membershipLabel
                      : 'unmatched',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const SectionSlab('Workloads'),
          _workloadsBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Events'),
          _eventsBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Changes'),
          _changesBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Networking'),
          _networkingBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Storage'),
          _storageBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Configuration'),
          _configBlock(c),
          const SizedBox(height: 10),
          const SectionSlab('Security'),
          _securityBlock(c),
        ],
      ],
    );
  }

  Widget _workloadsBlock(KelolaColors c) {
    final summary = _summary;
    final host = _host;
    final facts = _facts;
    return RiskBand(
      risk: RiskLevel.read,
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
              if (summary.crashLoopCount > 0)
                FilterPill(
                  label: '${summary.crashLoopCount} crashloop',
                  selected: true,
                  onTap: null,
                ),
              if (summary.pendingCount > 0)
                FilterPill(
                  label: '${summary.pendingCount} pending',
                  selected: true,
                  onTap: null,
                ),
              if (summary.restartingCount > 0)
                FilterPill(
                  label: '${summary.restartingCount} restarting',
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
                meta: workloadMeta(row),
                onTap: host == null || facts == null
                    ? null
                    : () => _openWorkload(row),
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

  // ---- Read-only sections (waves 2–4) --------------------------------

  Widget _box(KelolaColors c, List<Widget> children) {
    return RiskBand(
      risk: RiskLevel.read,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Loading / error / value gate shared by every read-only section.
  Widget _sectionBody<T>(
    KelolaColors c, {
    required T? value,
    required _SectionError? error,
    required List<Widget> Function(T value) build,
  }) {
    final v = value;
    if (error != null) {
      return _box(c, [
        Text(
          error.text,
          style: error.fromServer
              ? KelolaType.mono(color: c.muted, size: 12)
              : KelolaType.body(color: c.muted, size: 13),
        ),
      ]);
    }
    if (v == null) {
      return _box(c, [
        Text(
          _loading ? 'Reading…' : 'Not read yet',
          style: KelolaType.body(color: c.muted, size: 13),
        ),
      ]);
    }
    return _box(c, build(v));
  }

  Widget _pills(List<({String label, bool alert})> pills) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final p in pills)
          FilterPill(label: p.label, selected: p.alert, onTap: null),
      ],
    );
  }

  Widget _allButton(String label, String title, List<K8sListRow> rows,
      {String emptyCopy = 'Nothing to show.'}) {
    return OutlinedButton(
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => K8sResourceListScreen(
              hostId: widget.hostId,
              title: title,
              rows: rows,
              emptyCopy: emptyCopy,
            ),
          ),
        );
      },
      child: Text(label),
    );
  }

  /// Workload row an event points at, so tapping it opens logs + events.
  K8sWorkload? _workloadFor(K8sClusterEvent e) {
    final kind = parseK8sKind(e.objectKind);
    if (kind == null) {
      return null;
    }
    for (final row in _inv.rows) {
      if (row.kind == kind &&
          row.namespace == e.namespace &&
          row.name == e.objectName) {
        return row;
      }
    }
    return null;
  }

  void _openWorkload(K8sWorkload row) => _snapshot.openWorkload(context, row);

  List<K8sListRow> _eventRows(List<K8sClusterEvent> events) {
    final now = _now();
    return [
      for (final e in events)
        () {
          final target = _workloadFor(e);
          final age = k8sAge(e.at, now);
          return K8sListRow(
            name: e.reason.isEmpty ? e.objectLabel : e.reason,
            meta: [
              e.objectLabel,
              if (e.count > 1) '${e.count}×',
              if (age.isNotEmpty) age,
            ].join(' · '),
            detail: e.message.isEmpty ? null : e.message,
            status: e.warning ? HealthStatus.warning : HealthStatus.unknown,
            onTap: target == null ? null : () => _openWorkload(target),
          );
        }(),
    ];
  }

  Widget _eventsBlock(KelolaColors c) {
    return _sectionBody<List<K8sClusterEvent>>(
      c,
      value: _events,
      error: _eventsError,
      build: (events) {
        final now = _now();
        final lastHour = events
            .where((e) => e.at != null && now.difference(e.at!).inMinutes < 60)
            .length;
        final rows = _eventRows(events);
        return [
          _pills([
            (label: '${events.length} warnings', alert: events.isNotEmpty),
            (label: '$lastHour last hour', alert: lastHour > 0),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            K8sQuietNote('No warning events')
          else
            K8sRows(rows: rows, limit: 3),
          _allButton('All events', 'Events', rows,
              emptyCopy: 'No warning events.'),
        ];
      },
    );
  }

  K8sWorkload? _ownerOf(K8sRevision r) {
    for (final row in _inv.rows) {
      if (r.ownedBy(row)) {
        return row;
      }
    }
    return null;
  }

  List<K8sListRow> _changeRows(List<K8sRevision> revs) {
    final now = _now();
    return [
      for (final r in revs.take(200))
        () {
          final owner = _ownerOf(r);
          final age = r.ageLabel(now);
          return K8sListRow(
            name: r.ownerLabel,
            meta: [
              'rev ${r.revision}',
              if (r.current) 'current',
              if (age.isNotEmpty) age,
            ].join(' · '),
            detail: [
              r.changeLabel,
              if (r.changeCause.isNotEmpty) r.changeCause,
            ].join('\n'),
            status: r.current && owner != null
                ? owner.health
                : HealthStatus.unknown,
            onTap: owner == null ? null : () => _openWorkload(owner),
          );
        }(),
    ];
  }

  Widget _changesBlock(KelolaColors c) {
    return _sectionBody<List<K8sRevision>>(
      c,
      value: _changes,
      error: _changesError,
      build: (revs) {
        final now = _now();
        final day = revs
            .where(
              (r) => r.changedAt != null && now.difference(r.changedAt!).inHours < 24,
            )
            .length;
        final onUnhealthy = revs.where((r) {
          if (!r.current) {
            return false;
          }
          final h = _ownerOf(r)?.health;
          return h == HealthStatus.warning || h == HealthStatus.failed;
        }).length;
        final rows = _changeRows(revs);
        return [
          _pills([
            (label: '${revs.length} revisions', alert: false),
            (label: '$day last 24h', alert: false),
            if (onUnhealthy > 0)
              (label: '$onUnhealthy on unhealthy', alert: true),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            K8sQuietNote('No rollout history kept')
          else
            K8sRows(rows: rows, limit: 3),
          _allButton('All changes', 'Changes', rows,
              emptyCopy: 'No rollout history kept.'),
        ];
      },
    );
  }

  List<K8sListRow> _serviceRows(K8sNetworking net) {
    final sorted = [...net.services]
      ..sort((a, b) {
        final h = worstHealthFirst(a.health, b.health);
        return h != 0 ? h : a.title.compareTo(b.title);
      });
    return [
      for (final s in sorted)
        K8sListRow(
          name: s.title,
          meta: [
            s.type,
            s.endpointsLabel,
            if (s.ports.isNotEmpty) s.ports,
            if (s.loadBalancerPending) 'LB pending',
            if (s.externalAddress.isNotEmpty) s.externalAddress,
          ].join(' · '),
          status: s.health,
          onTap: () => _push(
            K8sServiceDetailScreen(snapshot: _snapshot, service: s),
          ),
        ),
    ];
  }

  Widget _networkingBlock(KelolaColors c) {
    return _sectionBody<K8sNetworking>(
      c,
      value: _net,
      error: _netError,
      build: (net) {
        final rows = _serviceRows(net);
        final problems =
            rows.where((r) => r.status != HealthStatus.healthy).toList();
        return [
          _pills([
            (label: '${net.services.length} svc', alert: false),
            if (net.noEndpointCount > 0)
              (label: '${net.noEndpointCount} no endpoints', alert: true),
            if (net.lbPendingCount > 0)
              (label: '${net.lbPendingCount} LB pending', alert: true),
          ]),
          const SizedBox(height: 10),
          if (problems.isEmpty)
            K8sQuietNote('All services have ready endpoints')
          else
            K8sRows(rows: problems, limit: 3),
          _allButton('All services', 'Services', rows,
              emptyCopy: 'No services.'),
        ];
      },
    );
  }

  List<K8sListRow> _storageRows(K8sStorage storage) {
    final rows = <K8sListRow>[
      for (final pvc in storage.claims)
        K8sListRow(
          name: pvc.title,
          meta: [
            'pvc',
            pvc.phase.isEmpty ? 'unknown' : pvc.phase,
            if ((pvc.capacity.isEmpty ? pvc.requested : pvc.capacity)
                .isNotEmpty)
              pvc.capacity.isEmpty ? pvc.requested : pvc.capacity,
            if (pvc.storageClass.isNotEmpty) pvc.storageClass,
          ].join(' · '),
          status: pvc.health,
          onTap: () => _push(
            K8sClaimDetailScreen(snapshot: _snapshot, claim: pvc),
          ),
        ),
      for (final pv in storage.volumes)
        K8sListRow(
          name: pv.name,
          meta: [
            'pv',
            pv.phase.isEmpty ? 'unknown' : pv.phase,
            if (pv.capacity.isNotEmpty) pv.capacity,
            if (pv.claim.isNotEmpty) pv.claim,
            if (pv.reclaimPolicy.isNotEmpty) pv.reclaimPolicy,
          ].join(' · '),
          status: pv.health,
          onTap: () => _push(
            K8sVolumeDetailScreen(snapshot: _snapshot, volume: pv),
          ),
        ),
    ];
    rows.sort((a, b) {
      final h = worstHealthFirst(a.status, b.status);
      return h != 0 ? h : a.name.compareTo(b.name);
    });
    return rows;
  }

  Widget _storageBlock(KelolaColors c) {
    return _sectionBody<K8sStorage>(
      c,
      value: _storage,
      error: _storageError,
      build: (storage) {
        final rows = _storageRows(storage);
        final problems =
            rows.where((r) => r.status != HealthStatus.healthy).toList();
        return [
          _pills([
            (label: '${storage.claims.length} pvc', alert: false),
            (label: '${storage.volumes.length} pv', alert: false),
            if (storage.pendingClaims > 0)
              (label: '${storage.pendingClaims} pending', alert: true),
            if (storage.lostClaims > 0)
              (label: '${storage.lostClaims} lost', alert: true),
            if (storage.unhealthyVolumes > 0)
              (label: '${storage.unhealthyVolumes} pv attention', alert: true),
          ]),
          const SizedBox(height: 10),
          if (problems.isEmpty)
            K8sQuietNote('All claims bound')
          else
            K8sRows(rows: problems, limit: 3),
          _allButton('All volumes', 'Storage', rows,
              emptyCopy: 'No persistent volumes or claims.'),
        ];
      },
    );
  }

  List<K8sListRow> _findingRows(List<K8sFinding> findings) {
    return [
      for (final f in findings)
        K8sListRow(
          name: f.subject,
          meta: f.issues.first,
          detail: f.issues.length > 1 ? f.issues.skip(1).join(' · ') : null,
          status: f.health,
          onTap: f.workload == null ? null : () => _openWorkload(f.workload!),
        ),
    ];
  }

  Widget _configBlock(KelolaColors c) {
    return _sectionBody<K8sConfigInventory>(
      c,
      value: _config,
      error: _configError,
      build: (inv) {
        final findings = configFindings(_inv.rows, inv);
        final missing =
            findings.where((f) => f.health == HealthStatus.failed).length;
        final hygiene = findings.length - missing;
        final rows = _findingRows(findings);
        return [
          _pills([
            (label: '${inv.configMapCount} cm', alert: false),
            (
              label: inv.secretsReadable
                  ? '${inv.secrets.length} secrets'
                  : 'secrets not readable',
              alert: false,
            ),
            if (missing > 0) (label: '$missing missing ref', alert: true),
            if (hygiene > 0) (label: '$hygiene hygiene', alert: true),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            K8sQuietNote('Refs resolve; requests, limits and probes set')
          else
            K8sRows(rows: rows, limit: 3),
          _allButton('All config findings', 'Configuration', rows,
              emptyCopy: 'No configuration findings.'),
        ];
      },
    );
  }

  Widget _securityBlock(KelolaColors c) {
    return _sectionBody<K8sSecurityInventory>(
      c,
      value: _security,
      error: _securityError,
      build: (sec) {
        final findings = securityFindings(_inv.rows, sec);
        final rows = _findingRows(findings);
        return [
          _pills([
            (label: '${sec.serviceAccounts} sa', alert: false),
            (
              label: '${sec.networkPolicyNamespaces.length} ns with netpol',
              alert: false,
            ),
            if (sec.clusterAdminGrants.isNotEmpty)
              (
                label: '${sec.clusterAdminGrants.length} cluster-admin',
                alert: true,
              ),
            if (findings.isNotEmpty)
              (label: '${findings.length} findings', alert: true),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            K8sQuietNote('No privileged or open findings')
          else
            K8sRows(rows: rows, limit: 3),
          _allButton('All security findings', 'Security', rows,
              emptyCopy: 'No security findings.'),
        ];
      },
    );
  }

  /// First three entries, then `+N`, so a big cluster cannot flood the band.
  String _cap(List<String> items) {
    if (items.length <= 3) {
      return items.join(', ');
    }
    return '${items.take(3).join(', ')} +${items.length - 3}';
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

/// A section that could not be read. [fromServer] is kubectl's own text
/// (mono, per the type rule); otherwise it is human-written SSH copy.
class _SectionError {
  const _SectionError(this.text, {required this.fromServer});

  final String text;
  final bool fromServer;
}
