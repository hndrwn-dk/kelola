import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/argo_probes.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/k8s_reader_probes.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/argo_apps_screen.dart';
import 'package:kelola/presentation/screens/k8s_resource_detail_screen.dart';
import 'package:kelola/presentation/screens/k8s_resource_list_screen.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/screens/workloads_screen.dart';
import 'package:kelola/presentation/widgets/argo_gitops_block.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';
import 'package:kelola/presentation/widgets/k8s_reader_flow.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/presentation/widgets/ocp_operator_sheet.dart';
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

  // M48: OpenShift section. Only read when the API says OpenShift.
  OpenShiftHealth? _ocp;
  _SectionError? _ocpError;
  DateTime? _ocpReadAt;
  OcpOperatorFilter _opFilter = OcpOperatorFilter.all;

  // M49: GitOps section. Only read when Argo CD is known to be installed
  // (fresh detection, else the cached record for the same context).
  bool? _argoKnown;
  ArgoApps? _argo;
  _SectionError? _argoError;
  DateTime? _argoReadAt;

  /// The Argo CD read in flight, shared by every load: a refresh never
  /// starts a second `get applications -A` while one is pending (sshd
  /// MaxSessions, see [_inFlight]).
  Future<({ArgoApps? value, _SectionError? error})>? _argoPending;

  /// M52e: the `kelola-reader` kubeconfig on this host; null where the host
  /// gets no reader (oc) or the check failed.
  K8sReaderStatus? _reader;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// True while a load runs. Pull-to-refresh during a load must not start
  /// a second batch: that doubles the cluster-wide reads on the API server
  /// and can exceed sshd's MaxSessions (10) on the pooled connection.
  bool _inFlight = false;

  /// M49: bumps per load, so a late GitOps result from an older load is
  /// dropped.
  int _loadGen = 0;

  Future<void> _load() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    final gen = ++_loadGen;
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
        if (factsNeedK8sRediscovery(facts)) {
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
      // M49: the cached record, read once. Never awaited on the main path:
      // only the GitOps section waits on it, when the fresh read cannot say.
      final cachedKind = _readClusterKind(host.id);
      // Cache the kind the band title is about to show, for the dashboard
      // tile. Only a read that answered replaces it.
      // Never awaited: a cache write must not delay or break the read.
      unawaited(_saveClusterKind(host.id, cluster));
      // M48 §3: an expired `oc login` is one state and nothing else.
      if (cluster.authExpired) {
        setState(() {
          _host = host;
          _facts = facts;
          _cluster = cluster;
          _inv = const WorkloadInventory(rows: []);
          _ocp = null;
          _ocpError = null;
          _setArgoKnown(null);
        });
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
      if (cluster.nodes.isNotEmpty) {
        // M48 §4: RHCOS hosts link back here from cached node names.
        await ref.read(hostRepositoryProvider).saveClusterNodeNames(
              hostId: host.id,
              summary: FleetK8sSummary.from(cluster, inv),
            );
        if (!mounted) {
          return;
        }
      }
      // M49: a fresh Argo CD answer wins; null waits for the cache below.
      final argoKnown = cluster.hasArgo;
      setState(() {
        _host = host;
        _facts = facts;
        _cluster = cluster.withCoreDns(dns);
        _inv = inv;
        // Unknown keeps the current state until the cache answers, so a
        // refresh does not hide and re-show the section.
        if (argoKnown != null) {
          _setArgoKnown(argoKnown);
        }
      });
      // Host key is pinned by now, so these can share the pooled client.
      // OpenShift health runs alongside Wave 2, only on OpenShift.
      final ocpFuture = cluster.isOpenShift == true
          ? _section(host, facts, const OpenShiftHealthProbe())
          : null;
      // M49: no SSH call unless Argo CD is known to be installed. Unknown
      // now: the cached record (same context only) decides, on its own.
      // Either way the GitOps result lands on its own, so the sections
      // below never wait on a slow `get applications -A`. A refresh while
      // it runs shares the pending read ([_argoPending]), never a second.
      if (argoKnown == true) {
        unawaited(_argoApply(host, facts, gen));
      } else if (argoKnown == null) {
        unawaited(_argoFromCache(host, facts, cluster, cachedKind, gen));
      }
      final results = await Future.wait([
        _section(host, facts, const ClusterEventsProbe()),
        _section(host, facts, const ServiceListProbe()),
        _section(host, facts, const StorageListProbe()),
        _section(host, facts, const ConfigInventoryProbe()),
        _section(host, facts, const SecurityInventoryProbe()),
        _section(host, facts, const RolloutHistoryProbe()),
      ]);
      final ocpResult = await ocpFuture;
      final reader = kelolaReaderSupported(kubectlFlavor(facts))
          ? await _section(host, facts, const K8sReaderStatusProbe())
          : null;
      if (!mounted) {
        return;
      }
      setState(() {
        _readAt = _now();
        _ocp = ocpResult?.value as OpenShiftHealth?;
        _ocpError = ocpResult?.error;
        _ocpReadAt = ocpResult == null ? null : _readAt;
        // M48.1: the version beats the node-image hint in the tile cache.
        final distro = _ocp?.version?.distro;
        if (distro != null) {
          unawaited(_saveDistro(host.id, distro, _readAt!));
        }
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
        _reader = reader?.value as K8sReaderStatus?;
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

  /// M49: fresh detection could not tell (null). Use the cached answer,
  /// folded with this read as the store will hold it, so a record from
  /// another kubeconfig context counts as unknown. Unknown or false: hidden,
  /// and no SSH call.
  Future<void> _argoFromCache(
    Host host,
    HostFacts facts,
    ClusterHealth cluster,
    Future<ClusterKindRecord?> cachedKind,
    int gen,
  ) async {
    final cached = await cachedKind;
    final known = mergeClusterKind(cached, cluster, _now())?.argoKnown;
    if (!mounted || gen != _loadGen) {
      return;
    }
    setState(() => _setArgoKnown(known));
    if (known != true) {
      return;
    }
    await _argoApply(host, facts, gen);
  }

  /// Reads Argo CD (or joins the read in flight) and shows it, unless a
  /// newer load started meanwhile.
  Future<void> _argoApply(Host host, HostFacts facts, int gen) async {
    final r = await _argoRead(host, facts);
    if (!mounted || gen != _loadGen) {
      return;
    }
    setState(() {
      _argo = r.value;
      _argoError = r.error;
      _argoReadAt = _now();
    });
  }

  /// Call inside setState. Anything but true also drops the last apps, so
  /// a read from another context cannot reappear later.
  void _setArgoKnown(bool? known) {
    _argoKnown = known;
    if (known != true) {
      _argo = null;
      _argoError = null;
      _argoReadAt = null;
    }
  }

  /// The pending Argo CD read, or a new one when none is in flight.
  Future<({ArgoApps? value, _SectionError? error})> _argoRead(
    Host host,
    HostFacts facts,
  ) {
    return _argoPending ??= _argoSection(host, facts).whenComplete(() {
      _argoPending = null;
    });
  }

  /// M49: [ArgoAppsProbe] reports an unreadable section on the value
  /// (Forbidden, timeout) instead of throwing; the home shows it as the
  /// section error, never as an empty list.
  Future<({ArgoApps? value, _SectionError? error})> _argoSection(
    Host host,
    HostFacts facts,
  ) async {
    final r = await _section(host, facts, ArgoAppsProbe(now: _now));
    final apps = r.value as ArgoApps?;
    final reason = apps?.error;
    if (reason != null) {
      return (
        value: null,
        error: _SectionError(
          K8sReadException('Argo CD applications', reason).toString(),
          fromServer: true,
        ),
      );
    }
    return (value: apps, error: r.error);
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
                : cluster.authExpired
                    ? 'session expired'
                    : _overallLabel(_bandStatus(cluster)),
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

    if (cluster != null && cluster.authExpired && _error == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kelolaScrollPadding(context),
        children: [_authExpiredBlock(c)],
      );
    }

    final openShift = cluster?.isOpenShift == true;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kelolaScrollPadding(context),
      children: [
        if (_error != null) ...[
          KelolaError(message: _error!, sudoUser: _host?.username),
          const SizedBox(height: 12),
        ],
        if (cluster != null && !cluster.missingKubectl) ...[
          SectionSlab(_clusterTitle(cluster)),
          RiskBand.forHealth(
            status: _bandStatus(cluster),
            child: FactGroup(
              heading: null,
              framed: false,
              entries: [
                FactEntry(
                  label: 'API server',
                  value: cluster.apiLabel,
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
                FactEntry(
                  label: openShift ? 'DNS' : 'CoreDNS',
                  value: _coreDnsLabel(cluster.coreDnsReady),
                ),
                FactEntry(
                  label: 'This host',
                  value: cluster.thisHostMatched && cluster.thisHost != null
                      ? cluster.thisHost!.membershipLabel
                      : 'unmatched',
                ),
              ],
            ),
          ),
          if (openShift) ...[
            const SizedBox(height: 10),
            SectionSlab(
              clusterKindLabel(true, distro: _distro(cluster)),
            ),
            _openShiftBlock(c, cluster),
          ],
          if (_argoKnown == true) ...[
            const SizedBox(height: 10),
            SectionSlab(argoSlabLabel(_argo)),
            _argoBlock(c),
          ],
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
          if (_reader != null) ...[
            const SizedBox(height: 10),
            const SectionSlab('Read access'),
            K8sReaderAccessBlock(
              status: _reader!,
              now: _now(),
              onSetUp: _loading ? null : _setUpReader,
              onRemove: _loading ? null : _removeReader,
            ),
          ],
        ],
      ],
    );
  }

  /// M52e: Enable Kelola sudo sets up the reader or renews its token.
  Future<void> _setUpReader() async {
    final host = _host;
    if (host == null) return;
    final ok = await runEnableKelolaSudoFlow(
      context: context,
      ref: ref,
      host: host,
      facts: _facts,
    );
    if (ok && mounted) await _load();
  }

  Future<void> _removeReader() async {
    final host = _host;
    final facts = _facts;
    if (host == null || facts == null) return;
    final ok = await runK8sReaderRemoveFlow(
      context: context,
      ref: ref,
      host: host,
      facts: facts,
    );
    if (ok && mounted) await _load();
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
              workloadsAllClearLine(
                apiReachable: _cluster?.apiReachable ?? false,
                rows: _inv.rows.length,
              ),
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

  // ---- M48: OpenShift ------------------------------------------------

  Future<void> _saveDistro(
    String hostId,
    OpenShiftDistro distro,
    DateTime at,
  ) async {
    try {
      final store = await ref.read(clusterKindStoreProvider.future);
      await store.recordDistro(hostId, distro, at);
    } catch (_) {
      // Cache only.
    }
  }

  Future<ClusterKindRecord?> _readClusterKind(String hostId) async {
    try {
      final store = await ref.read(clusterKindStoreProvider.future);
      return await store.read(hostId);
    } catch (_) {
      // Cache only; unknown hides the GitOps section.
      return null;
    }
  }

  Future<void> _saveClusterKind(String hostId, ClusterHealth cluster) async {
    try {
      final store = await ref.read(clusterKindStoreProvider.future);
      await store.recordRead(hostId, cluster, _now());
    } catch (_) {
      // Cache only; the dashboard tile keeps its last known label.
    }
  }

  /// OpenShift health with the cluster's nodes folded in (node MCD state).
  OpenShiftHealth? _ocpWith(ClusterHealth cluster) =>
      _ocp?.withNodes(cluster.nodes);

  /// Worse of the cluster's and the OpenShift section's own overall.
  HealthStatus _bandStatus(ClusterHealth cluster) {
    final ocp = _ocpWith(cluster);
    if (ocp == null) {
      return cluster.overall;
    }
    return worseHealth(cluster.overall, ocp.overall);
  }

  /// M48.1: the version wins; node OS images hint before it arrives.
  OpenShiftDistro? _distro(ClusterHealth cluster) =>
      _ocp?.version?.distro ?? cluster.distroHint;

  /// `OpenShift 4.17.3 · stable-4.17`; `OpenShift` until the version is
  /// read; `Kubernetes` off OpenShift.
  String _clusterTitle(ClusterHealth cluster) {
    if (cluster.isOpenShift != true) {
      return clusterKindLabel(cluster.isOpenShift);
    }
    final v = _ocp?.version;
    final base = clusterKindLabel(true, distro: _distro(cluster));
    if (v == null || v.version.isEmpty) {
      return base;
    }
    return [
      '$base ${v.version}',
      if (v.channel.isNotEmpty) v.channel,
    ].join(' · ');
  }

  Widget _authExpiredBlock(KelolaColors c) {
    final body = KelolaType.body(color: c.text, size: 13);
    return RiskBand.forHealth(
      status: HealthStatus.unknown,
      child: Text.rich(
        TextSpan(
          style: body,
          children: [
            const TextSpan(text: 'Session on this host expired. Run '),
            TextSpan(
              text: 'oc login',
              style: KelolaType.mono(color: c.text, size: 12.5),
            ),
            const TextSpan(text: ' there, then pull to refresh.'),
          ],
        ),
        key: const ValueKey('k8s-auth-expired'),
      ),
    );
  }

  List<K8sListRow> _nodeRows(Iterable<ClusterNodeMembership> nodes) {
    return [
      for (final n in nodes)
        K8sListRow(name: n.name, meta: n.nodeRowMeta, status: n.nodeHealth),
    ];
  }

  void _openNodes(String title, Iterable<ClusterNodeMembership> nodes) {
    _push(
      K8sResourceListScreen(
        hostId: widget.hostId,
        title: title,
        rows: _nodeRows(nodes),
        emptyCopy: 'No nodes match this pool.',
      ),
    );
  }

  void _openOperator(ClusterOperatorState op) {
    showOcpOperatorSheet(
      context,
      operator: op,
      asOf: k8sAge(_ocpReadAt, _now()),
    );
  }

  List<K8sListRow> _operatorRows(Iterable<ClusterOperatorState> ops) {
    final sorted = [...ops]
      ..sort((a, b) {
        final h = worstHealthFirst(a.health, b.health);
        return h != 0 ? h : a.name.compareTo(b.name);
      });
    return [
      for (final op in sorted)
        K8sListRow(
          name: op.name,
          meta: op.meta,
          status: op.health,
          onTap: () => _openOperator(op),
        ),
    ];
  }

  // ---- M49: Argo CD ----------------------------------------------------

  Widget _argoBlock(KelolaColors c) {
    final apps = _argo;
    if (_argoError != null || apps == null) {
      return _sectionBody<ArgoApps>(
        c,
        value: apps,
        error: _argoError,
        build: (_) => const [],
      );
    }
    return ArgoGitOpsBlock(
      apps: apps,
      now: _now(),
      onOpenApps: () => _openArgoApps(apps),
    );
  }

  void _openArgoApps(ArgoApps apps) {
    final host = _host;
    final facts = _facts;
    if (host == null || facts == null) {
      return;
    }
    _push(
      ArgoAppsScreen(
        host: host,
        facts: facts,
        apps: apps,
        workloads: _inv.rows,
        readAt: _argoReadAt ?? apps.readAt,
        now: _now,
      ),
    );
  }

  Widget _openShiftBlock(KelolaColors c, ClusterHealth cluster) {
    if (_ocpError != null || _ocp == null) {
      return _sectionBody<OpenShiftHealth>(
        c,
        value: _ocp,
        error: _ocpError,
        build: (_) => const [],
      );
    }
    final ocp = _ocpWith(cluster)!;
    final v = ocp.version;
    final updatingPools = [
      for (final p in ocp.pools ?? const <MachineConfigPoolState>[])
        if (p.updating) p.name,
    ];
    final pendingNodes = [
      for (final n in cluster.nodes)
        if (n.updatePending || n.mcdState == McdState.working) n.name,
    ];
    final facts = <FactEntry>[
      if (v != null && v.progressing)
        FactEntry(
          label: 'Progressing',
          value: v.progressingMessage.isEmpty ? 'yes' : v.progressingMessage,
        ),
      if (v != null && v.availableUpdates > 0)
        FactEntry(label: 'Updates', value: '${v.availableUpdates} available'),
      if (v != null && v.overrides > 0)
        FactEntry(
          label: 'Overrides',
          value: '${v.overrides} components unmanaged',
        ),
      if (updatingPools.isNotEmpty)
        FactEntry(label: 'Pools updating', value: _cap(updatingPools)),
      if (pendingNodes.isNotEmpty)
        FactEntry(label: 'Nodes updating', value: _cap(pendingNodes)),
      if (ocp.errorFor(OcpSection.clusterVersion) != null)
        FactEntry(
          label: 'Version',
          value: ocp.errorFor(OcpSection.clusterVersion)!,
        ),
    ];
    final ops = ocp.operators;
    final filtered = ops == null
        ? const <ClusterOperatorState>[]
        : [
            for (final op in ops)
              if (_opFilter.matches(op)) op,
          ];
    final opRows = _operatorRows(filtered);
    final pools = ocp.pools;
    final findings = ocp.findings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RiskBand.forHealth(
          status: ocp.overall,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ocp.summary,
                style: KelolaType.display(
                  color: c.text,
                  size: 14,
                  weight: FontWeight.w600,
                ),
              ),
              if (findings.isNotEmpty) ...[
                const SizedBox(height: 8),
                K8sRows(
                  rows: [
                    for (final f in findings)
                      K8sListRow(
                        name: f.subject,
                        meta: f.message,
                        status: f.health,
                      ),
                  ],
                  limit: 3,
                ),
              ],
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 6),
                FactGroup(heading: null, framed: false, entries: facts),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatCard(
                key: const ValueKey('ocp-stat-operators'),
                label: 'Operators',
                value: ocp.operatorsLabel,
                detail: ocp.errorFor(OcpSection.clusterOperators),
                meterFraction: ops == null || ops.isEmpty
                    ? null
                    : ocp.operatorsHealthy / ops.length,
                status: ops == null
                    ? null
                    : ocp.operatorsHealthy == ops.length
                        ? HealthStatus.healthy
                        : HealthStatus.failed,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatCard(
                key: const ValueKey('ocp-stat-pools'),
                label: 'Pools',
                value: ocp.poolsLabel,
                detail: ocp.errorFor(OcpSection.machineConfigPools),
                meterFraction: pools == null || pools.isEmpty
                    ? null
                    : ocp.poolsUpdated / pools.length,
                status: pools == null
                    ? null
                    : ocp.poolsDegraded > 0
                        ? HealthStatus.failed
                        : HealthStatus.healthy,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: StatCard(
                key: const ValueKey('ocp-stat-csrs'),
                label: 'CSRs',
                value: ocp.csrsLabel,
                detail: ocp.errorFor(OcpSection.csrs),
                status: ocp.csrs == null
                    ? null
                    : ocp.csrs!.count > 0
                        ? HealthStatus.warning
                        : HealthStatus.healthy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _box(c, [
          if (ops == null)
            Text(
              ocp.errorFor(OcpSection.clusterOperators) ??
                  'Could not read cluster operators',
              style: KelolaType.mono(color: c.muted, size: 12),
            )
          else ...[
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final f in OcpOperatorFilter.values)
                  FilterPill(
                    key: ValueKey('ocp-filter-${f.name}'),
                    label: '${f.label} ${f.count(ops)}',
                    selected: _opFilter == f,
                    onTap: () => setState(() => _opFilter = f),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (opRows.isEmpty)
              K8sQuietNote(_opFilter.emptyCopy)
            else
              K8sRows(rows: opRows, limit: 5),
            _allButton(
              'All operators',
              'Operators',
              _operatorRows(ops),
              emptyCopy: 'No cluster operators.',
            ),
          ],
        ]),
        const SizedBox(height: 8),
        _box(c, [
          if (pools == null)
            Text(
              ocp.errorFor(OcpSection.machineConfigPools) ??
                  'Could not read machine config pools',
              style: KelolaType.mono(color: c.muted, size: 12),
            )
          else if (pools.isEmpty)
            K8sQuietNote('No machine config pools')
          else
            K8sRows(
              rows: [
                for (final p in pools)
                  K8sListRow(
                    name: 'pool ${p.name}',
                    meta: p.meta,
                    status: p.health,
                    detail: p.degradedMessage.isNotEmpty
                        ? p.degradedMessage
                        : (p.updatingMessage.isNotEmpty
                            ? p.updatingMessage
                            : null),
                    onTap: () => _openNodes(
                      'Pool ${p.name}',
                      cluster.nodes.where(p.selects),
                    ),
                  ),
              ],
            ),
          OutlinedButton(
            onPressed: () => _openNodes('Nodes', cluster.nodes),
            child: const Text('All nodes'),
          ),
        ]),
      ],
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
