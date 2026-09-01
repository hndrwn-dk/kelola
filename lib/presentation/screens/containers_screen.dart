import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/providers.dart';

class ContainersScreen extends ConsumerStatefulWidget {
  const ContainersScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<ContainersScreen> createState() => _ContainersScreenState();
}

class _ContainersScreenState extends ConsumerState<ContainersScreen> {
  List<ContainerRow> _rows = const [];
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
      final rows = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: const ContainerListProbe(),
        facts: facts,
      );
      setState(() => _rows = rows);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Containers')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: colors.red)),
            if (!_loading && _rows.isEmpty && _error == null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No docker or podman on this host.',
                  style: TextStyle(color: colors.muted),
                ),
              ),
            for (final c in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  tileColor: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colors.line),
                  ),
                  title: Text(c.names.isEmpty ? c.id : c.names),
                  subtitle: Text(
                    [
                      c.image,
                      c.status,
                      if (c.ports.isNotEmpty) c.ports,
                      c.engine,
                    ].join(' · '),
                    style: TextStyle(color: colors.dim, fontSize: 12),
                  ),
                  trailing: Text(
                    c.running ? 'up' : c.state,
                    style: TextStyle(
                      color: c.running ? colors.green : colors.dim,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
