import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
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
  String? _user;
  String? _error;
  bool _loading = true;
  String? _openId;

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
        _user = host.username;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final rows = _inv.rows;
    final user = _user ?? 'USER';
    final groupCmd = 'sudo usermod -aG docker $user';
    return KelolaPage(
      title: 'Workloads',
      kicker: rows.isEmpty
          ? 'DOCKER · PODMAN · K3S'
          : '${rows.length} ${rows.first.namespace.isNotEmpty ? 'PODS' : 'CONTAINERS'}',
      busy: _loading,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_error != null)
              KelolaError(
                message: _error!,
                sudoUser: _host?.username,
              ),
            if (_inv.dockerDenied) ...[
              Text(
                'Docker is installed, but this SSH user cannot talk to the daemon.',
                style: KelolaFonts.title(size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'In a terminal you used sudo docker ps. Kelola will not prompt for a sudo password. Either add the user to the docker group, or grant NOPASSWD for docker.',
                style: TextStyle(color: colors.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              KelolaCommand(command: groupCmd),
              const SizedBox(height: 8),
              Text(
                'Then start a new SSH session (leave this host and connect again). Group membership does not apply to the current session.',
                style: TextStyle(color: colors.dim, height: 1.45, fontSize: 13),
              ),
              const SizedBox(height: 16),
            ],
            if (!_loading &&
                rows.isEmpty &&
                _error == null &&
                !_inv.dockerDenied)
              const KelolaEmpty(
                title: 'No workloads',
                body:
                    'No docker, podman, or Kubernetes pods found. Pull to refresh after installing an engine.',
              ),
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: KelolaSection(
                  '${rows.first.engine} · ${rows.length} '
                  '${rows.first.namespace.isNotEmpty ? 'pods' : 'containers'}',
                ),
              ),
            for (final c in rows) ...[
              KelolaWorkRow(
                title: c.title,
                subtitle: [
                  c.image,
                  c.status,
                  if (c.ports.isNotEmpty) c.ports,
                  c.engine,
                ].join(' · '),
                accent: c.running ? colors.green : colors.dim,
                trailing: Text(
                  c.running ? 'RUNNING' : c.state.toUpperCase(),
                  style: KelolaFonts.machine(
                    color: c.running ? colors.green : colors.dim,
                    size: 10,
                    weight: FontWeight.w500,
                  ),
                ),
                onTap: () => setState(
                  () => _openId = _openId == c.id ? null : c.id,
                ),
              ),
              if (_openId == c.id)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in _verbsFor(c))
                        OutlinedButton(
                          onPressed: _loading ? null : () => _act(c, v),
                          child: Text(v.name),
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<ContainerVerb> _verbsFor(ContainerRow row) {
    if (row.namespace.isNotEmpty) {
      return const [ContainerVerb.inspect];
    }
    if (row.running) {
      return const [
        ContainerVerb.stop,
        ContainerVerb.restart,
        ContainerVerb.pause,
        ContainerVerb.inspect,
      ];
    }
    final paused = row.state.toLowerCase().contains('paused');
    if (paused) {
      return const [ContainerVerb.unpause, ContainerVerb.inspect];
    }
    return const [
      ContainerVerb.start,
      ContainerVerb.restart,
      ContainerVerb.inspect,
    ];
  }

  Future<void> _act(ContainerRow row, ContainerVerb verb) async {
    final host = _host;
    if (host == null) {
      return;
    }
    if (verb != ContainerVerb.inspect) {
      final ok = await confirmHostAction(
        context,
        hostAlias: host.alias,
        title: '${verb.name} ${row.title}?',
        body: 'This changes container state on ${host.alias}.',
        confirmLabel: verb.name,
      );
      if (!ok || !mounted) {
        return;
      }
    }
    setState(() => _loading = true);
    try {
      final out = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: ContainerActionProbe(row: row, verb: verb),
        facts: _facts,
      );
      if (!mounted) {
        return;
      }
      if (verb == ContainerVerb.inspect) {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: Theme.of(context).extension<KelolaColors>()!.ink,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: SelectableText(
                out,
                style: KelolaFonts.machine(size: 11),
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${row.title}: ${verb.name}')),
        );
      }
      await _load();
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
