import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_view.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/workload_detail_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class WorkloadsScreen extends ConsumerStatefulWidget {
  const WorkloadsScreen({
    super.key,
    required this.hostId,
    this.factsOverride,
  });

  final String hostId;

  /// Test seam. Production always loads facts from the host.
  final HostFacts? factsOverride;

  @override
  ConsumerState<WorkloadsScreen> createState() => _WorkloadsScreenState();
}

class _WorkloadsScreenState extends ConsumerState<WorkloadsScreen> {
  Host? _host;
  HostFacts? _facts;
  WorkloadInventory _inv = const WorkloadInventory(rows: []);
  String? _error;
  bool _loading = true;
  String _namespace = '';
  K8sKind? _kind;
  bool _notReady = false;
  String _q = '';
  bool _searching = false;

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
        // Cached facts omit runtimes. Rediscover via HostFacts so the
        // list probe never probes PATH itself.
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
          _inv = const WorkloadInventory(rows: [], missingKubectl: true);
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
      setState(() {
        _host = host;
        _facts = facts;
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

  WorkloadListView get _view => WorkloadListView.build(
    _inv.rows,
    namespace: _namespace,
    kind: _kind,
    notReadyOnly: _notReady,
    query: _q,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final ns = workloadNamespaces(_inv.rows);
    return KelolaWashScaffold(
      appBar: KelolaHostAppBar(
        hostAlias: watchedHostAlias(ref, widget.hostId),
        title: 'Kubernetes',
        contextLine: _inv.missingKubectl
            ? 'no kubectl'
            : '${_inv.rows.length} objects',
        actions: [
          KelolaChromeIconButton(
            tooltip: 'Filter Kubernetes',
            icon: _searching ? Icons.search_off_rounded : Icons.search_rounded,
            onPressed: () => setState(() => _searching = !_searching),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_searching) ...[
                  TextField(
                    autofocus: true,
                    style: KelolaType.mono(color: c.text, size: 13),
                    decoration: InputDecoration(
                      hintText: 'Filter name or namespace',
                      hintStyle: KelolaType.mono(color: c.dim, size: 13),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    FilterPill(
                      label: _namespace.isEmpty ? 'NS ALL' : 'NS $_namespace',
                      selected: _namespace.isNotEmpty,
                      enabled: ns.isNotEmpty,
                      onTap: ns.isEmpty
                          ? null
                          : () {
                              if (_namespace.isEmpty) {
                                setState(() => _namespace = ns.first);
                                return;
                              }
                              final i = ns.indexOf(_namespace);
                              setState(() {
                                _namespace =
                                    i + 1 >= ns.length ? '' : ns[i + 1];
                              });
                            },
                    ),
                    FilterPill(
                      label: _kind == null ? 'KIND ALL' : _kind!.short.toUpperCase(),
                      selected: _kind != null,
                      onTap: () {
                        const kinds = K8sKind.values;
                        setState(() {
                          if (_kind == null) {
                            _kind = kinds.first;
                          } else {
                            final i = kinds.indexOf(_kind!);
                            _kind = i + 1 >= kinds.length ? null : kinds[i + 1];
                          }
                        });
                      },
                    ),
                    FilterPill(
                      label: 'NOT READY',
                      selected: _notReady,
                      onTap: () => setState(() => _notReady = !_notReady),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: KelolaError(
                message: _error!,
                sudoUser: _host?.username,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_inv.missingKubectl && !_loading && _error == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kelolaScrollPadding(context),
        children: const [KelolaEmpty(body: workloadEmptyCopy)],
      );
    }
    final view = _view;
    if (view.rows.isEmpty && !_loading && _error == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kelolaScrollPadding(context),
        children: const [KelolaEmpty(body: workloadNoneCopy)],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kelolaScrollPadding(context),
      itemCount: view.rows.length,
      itemBuilder: (context, i) {
        final row = view.rows[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: ServiceRow(
            risk: RiskLevel.read,
            status: row.health,
            name: row.title,
            meta: '${row.kind.short} · ${row.readyLabel}'
                '${row.phase.isEmpty ? '' : ' · ${row.phase}'}',
            onTap: () {
              final host = _host;
              final facts = _facts;
              if (host == null || facts == null) {
                return;
              }
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
        );
      },
    );
  }
}
