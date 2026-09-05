import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/presentation/assist_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
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
  static const _followCap = 1000;

  Host? _host;
  HostFacts? _facts;
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
  bool _live = false;
  bool _gone = false;
  bool _busySummarise = false;
  String? _older;
  JournalFollowHandle? _follow;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _priority = widget.unit != null ? 3 : null;
    _load(reset: true);
  }

  @override
  void dispose() {
    _gone = true;
    final follow = _follow;
    _follow = null;
    follow?.cancel();
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
        _facts = facts;
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
      if (_live) {
        await _startFollow();
      }
    } catch (e) {
      setState(() => _error = describeSshError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _prependFollow(JournalEntry e) {
    if (!mounted) {
      return;
    }
    if (!shouldAcceptFollowEntry(e, _entries)) {
      return;
    }
    setState(() {
      _entries.insert(0, e);
      if (_entries.length > _followCap) {
        _entries.removeRange(_followCap, _entries.length);
      }
    });
  }

  Future<void> _toggleLive() async {
    if (_live) {
      await _stopFollow();
      if (mounted) {
        setState(() => _live = false);
      }
      return;
    }
    setState(() => _live = true);
    await _startFollow();
  }

  Future<void> _startFollow() async {
    final host = _host;
    final facts = _facts;
    if (host == null || facts == null || !_live) {
      return;
    }
    await _stopFollow();
    try {
      final handle = await ref.read(sessionPoolProvider).startJournalFollow(
            host,
            facts: facts,
            unit: widget.unit,
            priority: _priority,
            grep: _q,
            onEntry: _prependFollow,
            onDenied: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _permissionDenied = true;
                _live = false;
              });
              _stopFollow();
            },
            onError: (e) {
              if (!mounted) {
                return;
              }
              setState(() => _error = describeSshError(e));
            },
            onClosed: () {
              if (!mounted || _gone) {
                return;
              }
              if (_live) {
                setState(() => _live = false);
              }
            },
            onUnknownHostKey: (hostId, algorithm, fingerprint) {
              return promptUnknownHostKey(
                context,
                hostId: hostId,
                algorithm: algorithm,
                fingerprint: fingerprint,
              );
            },
          );
      if (_gone || !mounted || !_live) {
        await handle.cancel();
        return;
      }
      _follow = handle;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeSshError(e);
          _live = false;
        });
      }
    }
  }

  Future<void> _stopFollow() async {
    final handle = _follow;
    _follow = null;
    await handle?.cancel();
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    _load(reset: true);
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
                      onTap: () => _setFilter(() => _priority = 3),
                    ),
                    FilterPill(
                      label: 'warn+',
                      selected: _priority == 4,
                      onTap: () => _setFilter(() => _priority = 4),
                    ),
                    FilterPill(
                      label: 'all',
                      selected: _priority == null,
                      onTap: () => _setFilter(() => _priority = null),
                    ),
                    FilterPill(
                      label: '1h',
                      selected: _lastHour,
                      onTap: () => _setFilter(() => _lastHour = !_lastHour),
                    ),
                    FilterPill(
                      label: 'live',
                      selected: _live,
                      onTap: _toggleLive,
                    ),
                  ],
                ),
                if (_entries.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ServiceRow(
                    risk: RiskLevel.read,
                    name: 'Summarise',
                    meta: 'assist · visible lines',
                    onTap: _busySummarise ? null : _summarise,
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _body(c)),
        ],
      ),
    );
  }

  Future<void> _summarise() async {
    final host = _host;
    if (host == null || _entries.isEmpty) {
      return;
    }
    setState(() => _busySummarise = true);
    try {
      final settings = await requireAssistSettings(ref);
      if (!mounted) {
        return;
      }
      final logs = _entries.take(80).map((e) => e.message).join('\n');
      final hostnames = [host.alias, host.address];
      final usernames = [host.username];
      final request = AssistRequest(
        system: 'Summarise these journal lines briefly. Do not invent events.',
        user: logs,
        hostnames: hostnames,
        usernames: usernames,
      );
      final text = await runAssistWithPreview(
        context: context,
        ref: ref,
        settings: settings,
        request: request,
        run: (s) => s.summariseLogs(
              settings: settings,
              logs: logs,
              hostnames: hostnames,
              usernames: usernames,
            ),
      );
      if (!mounted || text == null) {
        return;
      }
      await showAssistResult(context, title: 'Summary', body: text);
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busySummarise = false);
      }
    }
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
        padding: kelolaScrollPadding(context, left: 0, top: 10, right: 0),
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
