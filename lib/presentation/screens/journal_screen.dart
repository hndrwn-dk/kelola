import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/providers.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({
    super.key,
    required this.hostId,
    this.unit,
  });

  final String hostId;
  final String? unit;

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  Host? _host;
  final _entries = <JournalEntry>[];
  String? _error;
  bool _loading = true;
  bool _permissionDenied = false;
  bool _hasJournald = true;
  int? _priority;
  String _grep = '';
  String? _older;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries.clear();
        _older = null;
      }
    });
    try {
      final repo = ref.read(hostRepositoryProvider);
      final host = await repo.get(widget.hostId);
      if (host == null) {
        setState(() => _error = 'Host missing');
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      var facts = await repo.facts(host.id);
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
      final page = await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        probe: JournalProbe(
          unit: widget.unit,
          priority: _priority,
          grep: _grep,
          untilUsec: reset ? null : _older,
        ),
        facts: facts,
      );
      setState(() {
        _host = host;
        _hasJournald = page.hasJournald;
        _permissionDenied = page.permissionDenied;
        if (reset) {
          _entries.addAll(page.entries);
        } else {
          final seen = _entries.map((e) => e.cursor).toSet();
          _entries.addAll(
            page.entries.where((e) => !seen.contains(e.cursor)),
          );
        }
        _older = page.olderThanUsec;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.unit ?? _host?.alias ?? 'Logs'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'grep',
                    isDense: true,
                  ),
                  onSubmitted: (v) {
                    _grep = v;
                    _load(reset: true);
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _priority == null,
                      onSelected: (_) {
                        setState(() => _priority = null);
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('err'),
                      selected: _priority == 3,
                      onSelected: (_) {
                        setState(() => _priority = 3);
                        _load(reset: true);
                      },
                    ),
                    ChoiceChip(
                      label: const Text('warn'),
                      selected: _priority == 4,
                      onSelected: (_) {
                        setState(() => _priority = 4);
                        _load(reset: true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _body(colors)),
        ],
      ),
    );
  }

  Widget _body(KelolaColors colors) {
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(_error!, style: TextStyle(color: colors.red)),
          ),
        ],
      );
    }
    if (!_hasJournald) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This host has no journald.',
              style: TextStyle(color: colors.muted),
            ),
          ),
        ],
      );
    }
    if (_permissionDenied) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Journal is not readable. On the host: sudo usermod -aG systemd-journal ${_host?.username ?? 'USER'}',
              style: TextStyle(color: colors.muted),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _entries.length + 1,
        itemBuilder: (context, i) {
          if (i == _entries.length) {
            if (_entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No log lines.',
                  style: TextStyle(color: colors.muted),
                ),
              );
            }
            return TextButton(
              onPressed: _loading ? null : () => _load(reset: false),
              child: const Text('Older'),
            );
          }
          final e = _entries[i];
          final color = e.isError
              ? colors.red
              : e.isWarning
                  ? colors.amber
                  : colors.muted;
          final ts = e.timestamp;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (ts != null) ts.toIso8601String().substring(11, 19),
                    e.unit ?? e.syslogIdentifier ?? '',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: colors.dim, fontSize: 11),
                ),
                SelectableText(
                  e.message,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
