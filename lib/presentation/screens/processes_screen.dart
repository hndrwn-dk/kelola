import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/process_list_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/providers.dart';

class ProcessesScreen extends ConsumerStatefulWidget {
  const ProcessesScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends ConsumerState<ProcessesScreen> {
  List<ProcessRow> _rows = const [];
  String _q = '';
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
        probe: const ProcessListProbe(),
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
    final q = _q.trim().toLowerCase();
    final visible = q.isEmpty
        ? _rows
        : _rows
            .where(
              (p) =>
                  p.command.toLowerCase().contains(q) ||
                  p.user.toLowerCase().contains(q) ||
                  '${p.pid}'.contains(q),
            )
            .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Processes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter pid, user, command',
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!, style: TextStyle(color: colors.red)),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final p = visible[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: colors.surface,
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colors.line),
                      ),
                      title: Text(
                        p.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'pid ${p.pid} · ${p.user} · cpu ${p.cpu.toStringAsFixed(1)} · rss ${(p.rssKb / 1024).toStringAsFixed(0)} MiB',
                        style: TextStyle(color: colors.dim, fontSize: 11),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
