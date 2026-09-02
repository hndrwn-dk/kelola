import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/processes/process_list_view.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/process_list_probe.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_host_action.dart';
import 'package:kelola/providers.dart';

class ProcessesScreen extends ConsumerStatefulWidget {
  const ProcessesScreen({super.key, required this.hostId});

  final String hostId;

  @override
  ConsumerState<ProcessesScreen> createState() => _ProcessesScreenState();
}

class _ProcessesScreenState extends ConsumerState<ProcessesScreen> {
  Host? _host;
  HostFacts? _facts;
  List<ProcessRow> _rows = const [];
  String _q = '';
  bool _searching = false;
  ProcessSort _sort = ProcessSort.cpu;
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
      setState(() {
        _host = host;
        _facts = facts;
        _rows = rows;
      });
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<ProcessRow> get _visible {
    final q = _q.trim().toLowerCase();
    var rows = _rows;
    if (q.isNotEmpty) {
      rows = rows
          .where(
            (p) =>
                p.command.toLowerCase().contains(q) ||
                p.user.toLowerCase().contains(q) ||
                '${p.pid}'.contains(q),
          )
          .toList();
    }
    return sortProcesses(rows, _sort);
  }

  String get _kicker {
    final n = _rows.length;
    final by = switch (_sort) {
      ProcessSort.cpu => 'BY CPU',
      ProcessSort.memory => 'BY MEMORY',
      ProcessSort.name => 'BY NAME',
    };
    return n == 0 ? by : '$by · $n TOTAL';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final visible = _visible;

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
              'Processes',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              _kicker,
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
            tooltip: 'Filter pid, user, command',
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
                      hintText: 'Filter pid, user, command',
                      hintStyle: KelolaType.mono(color: c.dim, size: 13),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 5,
                  children: [
                    FilterPill(
                      label: 'CPU',
                      selected: _sort == ProcessSort.cpu,
                      onTap: () => setState(() => _sort = ProcessSort.cpu),
                    ),
                    FilterPill(
                      label: 'Memory',
                      selected: _sort == ProcessSort.memory,
                      onTap: () => setState(() => _sort = ProcessSort.memory),
                    ),
                    FilterPill(
                      label: 'Name',
                      selected: _sort == ProcessSort.name,
                      onTap: () => setState(() => _sort = ProcessSort.name),
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
              child: visible.isEmpty && !_loading
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            'No processes match this filter.',
                            textAlign: TextAlign.center,
                            style: KelolaType.body(color: c.muted, size: 14),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
                      itemCount: visible.length + 1,
                      itemBuilder: (context, i) {
                        if (i == visible.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "sshd and PID 1 can't be killed here",
                              textAlign: TextAlign.center,
                              style: KelolaType.mono(color: c.dim, size: 9.5),
                            ),
                          );
                        }
                        final p = visible[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ServiceRow(
                            risk: RiskLevel.read,
                            status: p.cpu >= 100
                                ? HealthStatus.warning
                                : HealthStatus.unknown,
                            name: p.command,
                            meta: processListMeta(p),
                            endValue: formatProcessCpu(p.cpu),
                            endMeta: formatProcessRss(p.rssKb),
                            onTap: () => _openProcess(p),
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

  Future<void> _openProcess(ProcessRow row) async {
    final host = _host;
    final facts = _facts;
    if (host == null) {
      return;
    }
    ProcessInspect? inspect;
    try {
      inspect = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: ProcessInspectProbe(row.pid),
        facts: facts,
      );
    } catch (_) {}
    if (!mounted) {
      return;
    }
    final children = _rows.where((p) => p.ppid == row.pid).toList();
    final c = context.kc;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface2,
      builder: (ctx) {
        final protected = isProtectedProcess(row);
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(row.command, style: KelolaType.display(color: c.text, size: 16)),
              const SizedBox(height: 4),
              Text(
                processListMeta(row),
                style: KelolaType.mono(color: c.dim, size: 9.5),
              ),
              if (inspect != null && inspect.exe.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(inspect.exe, style: KelolaType.mono(color: c.muted, size: 10.5)),
              ],
              if (children.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'TREE',
                  style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
                ),
                for (final child in children.take(12))
                  Text(
                    '${child.pid}  ${child.command}',
                    style: KelolaType.mono(color: c.muted, size: 10.5),
                  ),
              ],
              if (inspect != null && inspect.fds.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'FILE DESCRIPTORS',
                  style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
                ),
                SelectableText(
                  inspect.fds,
                  style: KelolaType.mono(color: c.muted, size: 10.5),
                ),
              ],
              const SizedBox(height: 16),
              if (protected)
                Text(
                  'PID 1 and sshd cannot be signaled from Kelola.',
                  style: KelolaType.body(color: c.dim, size: 12),
                )
              else ...[
                ServiceRow(
                  risk: RiskLevel.mutate,
                  name: 'SIGTERM',
                  meta: 'mutate · one confirmation',
                  onTap: () => _signal(ctx, row, ProcessSignal.term),
                ),
                const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.destructive,
                  name: 'SIGKILL',
                  meta: 'destructive · immediate',
                  onTap: () => _signal(ctx, row, ProcessSignal.kill),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _signal(
    BuildContext sheet,
    ProcessRow row,
    ProcessSignal signal,
  ) async {
    final host = _host;
    if (host == null) {
      return;
    }
    Navigator.of(sheet).pop();
    final ok = await confirmHostAction(
      context,
      hostAlias: host.alias,
      title:
          '${signal == ProcessSignal.kill ? 'SIGKILL' : 'SIGTERM'} ${row.pid}?',
      body: signal == ProcessSignal.kill
          ? 'This immediately kills ${row.command} on ${host.alias}.'
          : 'Ask ${row.command} to exit on ${host.alias}.',
      confirmLabel: signal == ProcessSignal.kill ? 'SIGKILL' : 'SIGTERM',
      risk: signal == ProcessSignal.kill
          ? RiskLevel.destructive
          : RiskLevel.mutate,
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      final msg = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: ProcessSignalProbe(
          pid: row.pid,
          signal: signal,
          commandName: row.command,
        ),
        facts: _facts,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    }
  }
}
