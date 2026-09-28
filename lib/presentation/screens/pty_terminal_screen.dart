import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/keep_awake/keep_awake.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/pty/pty_session.dart';
import 'package:kelola/presentation/ssh_host_key_flow.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';
import 'package:xterm/xterm.dart';

Future<void> openPtyTerminal(
  BuildContext context,
  WidgetRef _,
  Host host,
) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PtyTerminalScreen(host: host),
    ),
  );
}

class PtyTerminalScreen extends ConsumerStatefulWidget {
  const PtyTerminalScreen({super.key, required this.host});

  final Host host;

  @override
  ConsumerState<PtyTerminalScreen> createState() => _PtyTerminalScreenState();
}

class _PtyTerminalScreenState extends ConsumerState<PtyTerminalScreen> {
  late final Terminal _terminal;
  late final KeepAwake _keepAwake;
  PtyChannel? _channel;
  StreamSubscription<List<int>>? _stdout;
  String? _error;
  var _ctrl = false;
  var _opening = true;

  @override
  void initState() {
    super.initState();
    _keepAwake = ref.read(keepAwakeProvider);
    unawaited(_keepAwake.acquire('pty'));
    _terminal = Terminal(
      maxLines: 4000,
      onOutput: _onLocalOutput,
      onResize: (w, h, pw, ph) {
        _channel?.resize(w, h);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_open());
    });
  }

  @override
  void dispose() {
    unawaited(_keepAwake.release('pty'));
    unawaited(_stdout?.cancel());
    unawaited(_channel?.close());
    super.dispose();
  }

  void _onLocalOutput(String data) {
    if (_ctrl && data.isNotEmpty) {
      _ctrl = false;
      final code = data.codeUnitAt(0) & 0x1f;
      _channel?.write([code]);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _channel?.write(utf8.encode(data));
  }

  Future<void> _open() async {
    final size = MediaQuery.sizeOf(context);
    final viewH = size.height - 160;
    final dims = ptySizeFromView(size.width - 16, viewH);
    try {
      await ref.read(enrollmentProvider.notifier).ensureKey();
      if (!mounted) {
        return;
      }
      final channel = await ref.read(sessionPoolProvider).openPty(
            widget.host,
            cols: dims.$1,
            rows: dims.$2,
            onUnknownHostKey: (hostId, algorithm, fingerprint) {
              return promptUnknownHostKey(
                context,
                hostId: hostId,
                algorithm: algorithm,
                fingerprint: fingerprint,
              );
            },
          );
      if (!mounted) {
        await channel.close();
        return;
      }
      _channel = channel;
      _stdout = channel.session.stdout.listen(
        (chunk) {
          _terminal.write(utf8.decode(chunk, allowMalformed: true));
        },
        onError: (Object e) {
          if (mounted) {
            setState(() => _error = describeSshError(e));
          }
        },
      );
      setState(() => _opening = false);
    } on ReadOnlyViolation {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = 'This host is read-only.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = describeSshError(e);
        });
      }
    }
  }

  void _send(String data) {
    if (_ctrl) {
      _onLocalOutput(data);
      return;
    }
    _channel?.write(utf8.encode(data));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    _terminal.paste(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return KelolaPage(
      title: 'Terminal',
      bar: KelolaHostAppBar(
        hostAlias: widget.host.alias,
        title: 'Terminal',
        actions: [
          KelolaChromeIconButton(
            icon: Icons.content_paste,
            tooltip: 'Paste',
            onPressed: _paste,
          ),
        ],
      ),
      busy: _opening,
      body: Column(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: KelolaError(
                message: _error!,
                sudoUser: widget.host.username,
              ),
            ),
          Expanded(
            child: TerminalView(
              _terminal,
              autofocus: true,
              deleteDetection: true,
              theme: _theme(c),
              textStyle: const TerminalStyle(
                fontFamily: 'IBMPlexMono',
                fontSize: 12,
              ),
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            ),
          ),
          Material(
            color: c.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  FilterPill(
                    label: 'Tab',
                    selected: false,
                    onTap: () => _send('\t'),
                  ),
                  FilterPill(
                    label: 'Esc',
                    selected: false,
                    onTap: () => _send('\x1b'),
                  ),
                  FilterPill(
                    label: 'Ctrl',
                    selected: _ctrl,
                    onTap: () => setState(() => _ctrl = !_ctrl),
                  ),
                  FilterPill(
                    label: 'Up',
                    selected: false,
                    onTap: () => _send('\x1b[A'),
                  ),
                  FilterPill(
                    label: 'Dn',
                    selected: false,
                    onTap: () => _send('\x1b[B'),
                  ),
                  FilterPill(
                    label: 'Lt',
                    selected: false,
                    onTap: () => _send('\x1b[D'),
                  ),
                  FilterPill(
                    label: 'Rt',
                    selected: false,
                    onTap: () => _send('\x1b[C'),
                  ),
                  FilterPill(
                    label: '|',
                    selected: false,
                    onTap: () => _send('|'),
                  ),
                  FilterPill(
                    label: '/',
                    selected: false,
                    onTap: () => _send('/'),
                  ),
                  FilterPill(
                    label: '-',
                    selected: false,
                    onTap: () => _send('-'),
                  ),
                  FilterPill(
                    label: '~',
                    selected: false,
                    onTap: () => _send('~'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TerminalTheme _theme(KelolaColors c) {
    return TerminalTheme(
      cursor: c.amber,
      selection: c.amber.withValues(alpha: 0.28),
      foreground: c.text,
      background: c.ink,
      black: c.ink,
      red: c.red,
      green: c.green,
      yellow: c.amber,
      blue: c.blue,
      magenta: c.amber,
      cyan: c.blue,
      white: c.text,
      brightBlack: c.dim,
      brightRed: c.red,
      brightGreen: c.green,
      brightYellow: c.amber,
      brightBlue: c.blue,
      brightMagenta: c.amber,
      brightCyan: c.blue,
      brightWhite: c.text,
      searchHitBackground: c.surface2,
      searchHitBackgroundCurrent: c.amber,
      searchHitForeground: c.ink,
    );
  }
}
