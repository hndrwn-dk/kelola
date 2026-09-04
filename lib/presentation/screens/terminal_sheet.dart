import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
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
    builder: (_) => SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: CommandSheet(host: host),
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
  final _scroll = ScrollController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final line = _input.text.trim();
    if (line.isEmpty || _busy) {
      return;
    }
    _input.clear();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final result = await runHostProbe(
        ref: ref,
        context: context,
        host: widget.host,
        probe: CommandRunnerProbe(line),
      );
      if (!mounted) {
        return;
      }
      if (_out.isNotEmpty) {
        _out.write('\n\n');
      }
      _out.write(formatCommandRun(line, result));
      setState(() {});
      _jump();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _error = describeSshError(e));
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

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Material(
      color: c.ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Command', style: KelolaType.display(color: c.text, size: 18)),
            const SizedBox(height: 4),
            Text(
              '${widget.host.alias} · NO PTY · AUDITED',
              style: KelolaType.mono(color: c.dim, size: 9.5, letterSpacing: 0.6),
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
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: _out.isEmpty
                      ? Text(
                          commandRunnerEmptyCopy,
                          style: KelolaType.body(color: c.muted, size: 13),
                        )
                      : SelectableText(
                          _out.toString(),
                          style: KelolaType.mono(color: c.text, size: 12)
                              .copyWith(height: 1.45),
                        ),
                ),
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
            const SizedBox(height: 8),
            ServiceRow(
              risk: RiskLevel.read,
              name: 'Propose',
              meta: 'assist · catalog only',
              onTap: _busy ? null : _propose,
            ),
          ],
        ),
      ),
    );
  }
}
