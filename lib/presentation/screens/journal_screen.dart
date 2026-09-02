import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/presentation/host_session.dart';
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
  String? _emptyHint;
  bool _loading = true;
  bool _permissionDenied = false;
  bool _hasJournald = true;
  late int? _priority;
  String _q = '';
  bool _searching = false;
  bool _lastHour = false;
  String? _older;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _priority = widget.unit != null ? 3 : null;
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? get _sinceUsec {
    if (!_lastHour) {
      return null;
    }
    return DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 1))
        .microsecondsSinceEpoch
        .toString();
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
          grep: _q,
          untilUsec: reset ? null : _older,
          sinceUsec: _sinceUsec,
        ),
        facts: facts,
      );
      setState(() {
        _host = host;
        _hasJournald = page.hasJournald;
        _permissionDenied = page.permissionDenied;
        _emptyHint = page.emptyHint;
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

  JournalLineKind _kind(JournalEntry e) {
    if (e.isError) {
      return JournalLineKind.error;
    }
    if (e.isWarning) {
      return JournalLineKind.warning;
    }
    return JournalLineKind.info;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final kicker = journalKicker(unit: widget.unit, priority: _priority);

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logs', style: KelolaType.display(color: c.text, size: 16)),
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
            tooltip: 'Filter message',
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
                      hintText: 'Filter message',
                      hintStyle: KelolaType.mono(color: c.dim, size: 13),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      _q = v;
                      _load(reset: true);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    FilterPill(
                      label: 'err+',
                      selected: _priority == 3,
                      onTap: () {
                        setState(() => _priority = 3);
                        _load(reset: true);
                      },
                    ),
                    FilterPill(
                      label: 'warn+',
                      selected: _priority == 4,
                      onTap: () {
                        setState(() => _priority = 4);
                        _load(reset: true);
                      },
                    ),
                    FilterPill(
                      label: 'all',
                      selected: _priority == null,
                      onTap: () {
                        setState(() => _priority = null);
                        _load(reset: true);
                      },
                    ),
                    FilterPill(
                      label: '1h',
                      selected: _lastHour,
                      onTap: () {
                        setState(() => _lastHour = !_lastHour);
                        _load(reset: true);
                      },
                    ),
                    FilterPill(
                      label: 'live',
                      selected: false,
                      enabled: false,
                      onTap: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Widget _body(KelolaColors c) {
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: KelolaError(
              message: _error!,
              sudoUser: _host?.username,
            ),
          ),
        ],
      );
    }
    if (!_hasJournald) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Text(
                  'No journald',
                  textAlign: TextAlign.center,
                  style: KelolaType.display(color: c.text, size: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'This host has no systemd journal.',
                  textAlign: TextAlign.center,
                  style: KelolaType.body(color: c.muted, size: 14),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_permissionDenied) {
      final cmd =
          'sudo usermod -aG systemd-journal ${_host?.username ?? 'USER'}';
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Journal is not readable over this SSH user.',
            style: KelolaType.display(color: c.text, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Kelola tried journalctl, then sudo -n journalctl. Both returned nothing. Grant the group, then open a new SSH session (disconnect in the app and reconnect).',
            style: KelolaType.body(color: c.muted, size: 13),
          ),
          const SizedBox(height: 12),
          SelectableText(cmd, style: KelolaType.mono(color: c.text, size: 12)),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 24),
        itemCount: _entries.length + 1,
        itemBuilder: (context, i) {
          if (i == _entries.length) {
            if (_entries.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 14),
                child: Text(
                  _emptyHint ??
                      'No log lines for this filter. Pull to refresh, or switch err+ / warn+ / all.',
                  style: KelolaType.body(color: c.muted, size: 13),
                ),
              );
            }
            return TextButton(
              onPressed: _loading ? null : () => _load(reset: false),
              child: Text(
                'Older',
                style: KelolaType.display(color: c.amber, size: 13),
              ),
            );
          }
          final e = _entries[i];
          final ts = e.timestamp;
          return JournalLogLine(
            timestamp: ts == null ? '' : journalClock(ts),
            message: e.message,
            kind: _kind(e),
          );
        },
      ),
    );
  }
}
