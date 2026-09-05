import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/screens/container_detail_screen.dart';
import 'package:kelola/presentation/screens/container_images_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class ContainersScreen extends ConsumerStatefulWidget {
  const ContainersScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends ConsumerState<ContainersScreen> {
  Host? _host;
  HostFacts? _facts;
  ContainerInventory _inv = const ContainerInventory(rows: []);
  String? _error;
  bool _loading = true;
  ContainerListFilter _filter = ContainerListFilter.all;
  String _q = '';
  bool _searching = false;
  bool _landed = false;

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
      var facts = await ref.read(hostRepositoryProvider).facts(host.id);
      if (!mounted) {
        return;
      }
      facts ??= await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const HostFactsProbe(),
      );
      if (!mounted) {
        return;
      }
      final inv = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const ContainerListProbe(),
        facts: facts,
      );
      setState(() {
        _host = host;
        _facts = facts;
        _inv = inv;
        if (!_landed) {
          _filter = defaultContainerListFilter(inv.rows);
          _landed = true;
        }
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ContainerListView get _view =>
      ContainerListView.build(_inv.rows, _filter, query: _q);

  String get _engine {
    if (_inv.rows.any((r) => r.engine == 'podman') &&
        !_inv.rows.any((r) => r.engine == 'docker')) {
      return 'podman';
    }
    if (_inv.engines.contains('podman') &&
        !_inv.engines.contains('docker')) {
      return 'podman';
    }
    return 'docker';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final counts = ContainerListCounts.from(_inv.rows);
    final kicker = containerListKicker(_inv.rows, engines: _inv.engines);

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
              'Containers',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              kicker,
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Images',
            icon: const Icon(Icons.sd_storage_outlined),
            onPressed: _host == null
                ? null
                : () async {
                    final host = _host!;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ContainerImagesScreen(
                          host: host,
                          facts: _facts ?? HostFacts.undiscovered,
                          engine: _engine,
                        ),
                      ),
                    );
                  },
          ),
          IconButton(
            tooltip: 'Filter containers',
            icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded,
            ),
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
                      hintText: 'Filter containers',
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
                    for (final filter in ContainerListFilter.values)
                      FilterPill(
                        label: containerListChipLabel(filter, counts),
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
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
    final view = _view;
    final user = _host?.username ?? 'USER';
    final children = <Widget>[];

    if (_inv.dockerDenied) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActionableError(
            title: 'Cannot talk to Docker',
            body:
                'Docker is installed, but this SSH user cannot talk to the daemon. '
                'Kelola will not prompt for a sudo password. Add the user to the docker group. '
                'A mutate that needs the engine will show a command-specific NOPASSWD rule. '
                'Then start a new SSH session — group membership '
                'does not apply to the current session.',
            snippet: 'sudo usermod -aG docker $user',
          ),
        ),
      );
    }

    if (!_loading && view.isEmpty && _error == null) {
      children.add(
        KelolaEmpty(
          body: _inv.rows.isEmpty && !_inv.dockerDenied && _q.isEmpty
              ? 'No docker or podman containers found. Pull to refresh after installing an engine.'
              : containerListEmptyCopy(_filter, query: _q),
        ),
      );
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: kelolaScrollPadding(context),
        children: children,
      );
    }

    for (final group in view.groups) {
      children.add(
        SectionSlab(
          group.label == 'STANDALONE'
              ? 'STANDALONE'
              : 'Stack · ${group.label}',
        ),
      );
      for (final row in group.rows) {
        children.add(_row(row));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: kelolaScrollPadding(context),
      children: children,
    );
  }

  Widget _row(ContainerRow row) {
    final health = _health(row);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ServiceRow(
        risk: RiskLevel.read,
        status: health,
        name: row.title,
        meta: containerListMeta(row),
        pillText: containerListPill(row),
        pillStatus: health,
        onTap: () => _open(row),
      ),
    );
  }

  HealthStatus _health(ContainerRow row) {
    return switch (containerHealth(row)) {
      ContainerHealth.healthy => HealthStatus.healthy,
      ContainerHealth.warning => HealthStatus.warning,
      ContainerHealth.failed => HealthStatus.failed,
      ContainerHealth.unknown => HealthStatus.unknown,
    };
  }

  Future<void> _open(ContainerRow row) async {
    final host = _host;
    if (host == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContainerDetailScreen(
          host: host,
          facts: _facts ?? HostFacts.undiscovered,
          row: row,
        ),
      ),
    );
    await _load();
  }
}
