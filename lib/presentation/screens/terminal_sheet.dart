import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/command_history/command_complete.dart';
import 'package:kelola/domain/command_history/command_history.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/session_logs/session_log.dart';
import 'package:kelola/domain/keep_awake/keep_awake.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/presentation/assist_flow.dart';
import 'package:kelola/presentation/assist_proposal.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/providers.dart';

Future<void> openCommandSheet(BuildContext context, WidgetRef ref, Host host) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.kc.ink,
    builder: (ctx) => KelolaSheet(
      child: SizedBox(
        height: kelolaSheetBodyHeight(ctx),
        child: CommandSheet(host: host),
      ),
    ),
  );
}

class CommandSheet extends ConsumerStatefulWidget {
  const CommandSheet({super.key, required this.host});

  final Host host;

  @override
  ConsumerState<CommandSheet> createState() => _CommandSheetState();
}

class _CommandSheetState extends ConsumerState<CommandSheet> {
  final _out = StringBuffer();
  final _input = TextEditingController();
  final _historySearch = TextEditingController();
  final _logSearch = TextEditingController();
  final _scroll = ScrollController();
  String? _error;
  bool _busy = false;
  bool _historyOpen = false;
  bool _logsOpen = false;
  List<String> _history = const [];
  List<SessionLog> _logs = const [];
  List<String> _completeHistory = const [];
  late final KeepAwake _keepAwake;

  @override
  void initState() {
    super.initState();
    _keepAwake = ref.read(keepAwakeProvider);
    _input.addListener(_onInputChanged);
    unawaited(_keepAwake.acquire('command'));
    unawaited(_reloadCompleteHistory());
  }

  @override
  void dispose() {
    unawaited(_keepAwake.release('command'));
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _historySearch.dispose();
    _logSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final line = _input.text.trim();
    if (line.isEmpty || _busy) {
      return;
    }
    await ref
        .read(hostRepositoryProvider)
        .recordCommandHistory(widget.host.id, line);
    unawaited(_reloadCompleteHistory());
    if (!mounted) {
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _error = null;
      _historyOpen = false;
      _logsOpen = false;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final env = await ref.read(hostRepositoryProvider).envForHost(widget.host);
      if (!mounted) {
        return;
      }
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: CommandRunnerProbe(line, env: env),
      );
      if (!mounted) {
        return;
      }
      final formatted = formatCommandRun(line, result);
      if (_out.isNotEmpty) {
        _out.write('\n\n');
      }
      _out.write(formatted);
      await ref.read(hostRepositoryProvider).recordSessionLog(
            widget.host.id,
            title: line,
            body: formatted,
          );
      if (!mounted) {
        return;
      }
      setState(() {});
      _jump();
    } catch (e) {
      if (!mounted) {
        return;
      }
      final message = describeSshError(e);
      await ref.read(hostRepositoryProvider).recordSessionLog(
            widget.host.id,
            title: line,
            body: message,
          );
      if (!mounted) {
        return;
      }
      setState(() => _error = message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _propose() async {
    final intent = _input.text.trim();
    if (intent.isEmpty || _busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await requireAssistSettings(ref);
      if (!mounted) {
        return;
      }
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final assistCtx = await loadAssistContext(
        ref: ref,
        context: context,
        host: widget.host,
      );
      if (!mounted) {
        return;
      }
      final host = widget.host;
      final hostnames = [host.alias, host.address];
      final usernames = [host.username];
      final request = intentAssistRequest(
        intent: intent,
        context: assistCtx,
        hostnames: hostnames,
        usernames: usernames,
      );
      final proposal = await runAssistWithPreview(
        context: context,
        ref: ref,
        settings: settings,
        request: request,
        run: (s) => s.proposeFromIntent(
          settings: settings,
          intent: intent,
          context: assistCtx,
          hostnames: hostnames,
          usernames: usernames,
        ),
      );
      if (!mounted || proposal == null) {
        return;
      }
      await showAssistProposalSheet(
        context,
        host: host,
        proposal: proposal,
        onRun: (p) async {
          try {
            await runProposedProbe(
              context: context,
              ref: ref,
              host: host,
              proposal: p,
            );
            if (!mounted) {
              return;
            }
            if (_out.isNotEmpty) {
              _out.write('\n\n');
            }
            _out.write(
              '# assist ran ${p.probeKind}'
              '${p.unit != null ? ' ${p.unit}' : ''}'
              '${p.path != null ? ' ${p.path}' : ''}',
            );
            setState(() {});
            _jump();
          } catch (e) {
            if (mounted) {
              setState(() => _error = describeSshError(e));
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _toggleHistory() async {
    if (_busy) {
      return;
    }
    if (_historyOpen) {
      setState(() => _historyOpen = false);
      return;
    }
    final items = await ref
        .read(hostRepositoryProvider)
        .listCommandHistory(widget.host.id);
    if (!mounted) {
      return;
    }
    _historySearch.clear();
    setState(() {
      _historyOpen = true;
      _logsOpen = false;
      _history = items;
    });
  }

  Future<void> _toggleLogs() async {
    if (_busy) {
      return;
    }
    if (_logsOpen) {
      setState(() => _logsOpen = false);
      return;
    }
    final items = await ref
        .read(hostRepositoryProvider)
        .listSessionLogs(widget.host.id);
    if (!mounted) {
      return;
    }
    _logSearch.clear();
    setState(() {
      _logsOpen = true;
      _historyOpen = false;
      _logs = items;
    });
  }

  void _onInputChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _reloadCompleteHistory() async {
    final items = await ref
        .read(hostRepositoryProvider)
        .listCommandHistory(widget.host.id);
    if (!mounted) {
      return;
    }
    setState(() => _completeHistory = items);
  }

  void _pickHistory(String line) {
    _input.value = TextEditingValue(
      text: line,
      selection: TextSelection.collapsed(offset: line.length),
    );
    setState(() => _historyOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final suggestions = (!_historyOpen && !_logsOpen && !_busy)
        ? completeCommandLines(query: _input.text, history: _completeHistory)
        : const <String>[];
    return Material(
      color: c.ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KelolaHostIdentity(
              hostAlias: widget.host.alias,
              title: 'Command',
              contextLine: 'NO PTY',
            ),
            const SizedBox(height: 10),
            if (_busy)
              LinearProgressIndicator(
                minHeight: 1.5,
                backgroundColor: c.surface,
                color: c.amber,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: KelolaError(
                  message: _error!,
                  sudoUser: widget.host.username,
                ),
              ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(KelolaRadii.md),
                  border: Border.all(color: c.line),
                ),
                child: _historyOpen
                    ? _historyPane(c)
                    : _logsOpen
                        ? _logsPane(c)
                        : _outputPane(c),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _input,
              enabled: !_busy,
              style: KelolaType.mono(color: c.text, size: 13),
              decoration: InputDecoration(
                hintText: 'one command or intent',
                hintStyle: KelolaType.body(color: c.dim, size: 13),
                isDense: true,
              ),
              onSubmitted: (_) => _send(),
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 168),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final line = suggestions[i];
                    return InkWell(
                      onTap: () => _pickHistory(line),
                      child: RiskBand(
                        risk: RiskLevel.read,
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KelolaType.mono(color: c.text, size: 12),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Propose',
              meta: 'assist · catalog only',
              onTap: _busy ? null : _propose,
            ),
            const SizedBox(height: 8),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'History',
              meta: _historyOpen ? 'close' : 'this host',
              onTap: _busy ? null : _toggleHistory,
            ),
            const SizedBox(height: 8),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Logs',
              meta: _logsOpen ? 'close' : 'this host',
              onTap: _busy ? null : _toggleLogs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _outputPane(KelolaColors c) {
    return SingleChildScrollView(
      controller: _scroll,
      child: _out.isEmpty
          ? Text(
              commandRunnerEmptyCopy,
              style: KelolaType.body(color: c.muted, size: 13),
            )
          : SelectableText(
              _out.toString(),
              style: KelolaType.mono(
                color: c.text,
                size: 12,
              ).copyWith(height: 1.45),
            ),
    );
  }

  Widget _historyPane(KelolaColors c) {
    final filtered = filterCommandHistory(_history, _historySearch.text);
    final emptyCopy = _historySearch.text.trim().isEmpty
        ? commandHistoryEmptyCopy
        : commandHistoryNoMatchCopy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _historySearch,
          style: KelolaType.mono(color: c.text, size: 13),
          decoration: InputDecoration(
            hintText: 'search commands',
            hintStyle: KelolaType.body(color: c.dim, size: 13),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Text(
                  emptyCopy,
                  style: KelolaType.body(color: c.muted, size: 13),
                )
              : ListView.separated(
                  padding: kelolaScrollPadding(
                    context,
                    left: 0,
                    top: 0,
                    right: 0,
                    extraBottom: 8,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final line = filtered[i];
                    return InkWell(
                      onTap: () => _pickHistory(line),
                      child: RiskBand(
                        risk: RiskLevel.read,
                        child: Text(
                          line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KelolaType.mono(color: c.text, size: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _logsPane(KelolaColors c) {
    final filtered = filterSessionLogs(_logs, _logSearch.text);
    final emptyCopy = _logSearch.text.trim().isEmpty
        ? sessionLogEmptyCopy
        : sessionLogNoMatchCopy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _logSearch,
          style: KelolaType.mono(color: c.text, size: 13),
          decoration: InputDecoration(
            hintText: 'search session logs',
            hintStyle: KelolaType.body(color: c.dim, size: 13),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: filtered.isEmpty
              ? Text(
                  emptyCopy,
                  style: KelolaType.body(color: c.muted, size: 13),
                )
              : ListView.separated(
                  padding: kelolaScrollPadding(
                    context,
                    left: 0,
                    top: 0,
                    right: 0,
                    extraBottom: 8,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final log = filtered[i];
                    return InkWell(
                      onTap: () => _pickLog(log),
                      onLongPress: () => _toggleLogBookmark(log),
                      child: RiskBand(
                        risk: RiskLevel.read,
                        child: Text(
                          log.bookmarked ? '${log.title} · kept' : log.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KelolaType.mono(color: c.text, size: 12),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _pickLog(SessionLog log) {
    _out
      ..clear()
      ..write(log.body);
    setState(() => _logsOpen = false);
    _jump();
  }

  Future<void> _toggleLogBookmark(SessionLog log) async {
    await ref
        .read(hostRepositoryProvider)
        .setSessionLogBookmarked(log.id, !log.bookmarked);
    final items = await ref
        .read(hostRepositoryProvider)
        .listSessionLogs(widget.host.id);
    if (!mounted) {
      return;
    }
    setState(() => _logs = items);
  }
}
