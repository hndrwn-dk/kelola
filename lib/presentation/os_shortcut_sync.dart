import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/shortcuts/shortcuts_channel.dart';
import 'package:kelola/domain/shortcuts/os_shortcuts.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';
import 'package:kelola/providers.dart';

class OsShortcutSync extends ConsumerStatefulWidget {
  const OsShortcutSync({
    super.key,
    required this.child,
    this.channel,
  });

  final Widget child;
  final ShortcutsChannel? channel;

  @override
  ConsumerState<OsShortcutSync> createState() => _OsShortcutSyncState();
}

class _OsShortcutSyncState extends ConsumerState<OsShortcutSync> {
  late final ShortcutsChannel _channel =
      widget.channel ?? ShortcutsChannel();
  List<OsShortcut> _last = const [];

  @override
  Widget build(BuildContext context) {
    final lastId = ref.watch(lastHostIdProvider).valueOrNull;
    final targets = lastId == null
        ? const <TunnelTarget>[]
        : (ref.watch(tunnelTargetsProvider(lastId)).valueOrNull ??
            const <TunnelTarget>[]);
    final items = buildOsShortcuts(
      lastHostId: lastId,
      lastHostHasTunnelTarget: targets.isNotEmpty,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _same(items, _last)) {
        return;
      }
      _last = items;
      unawaited(_channel.set(items));
    });
    return widget.child;
  }

  bool _same(List<OsShortcut> a, List<OsShortcut> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].uri != b[i].uri) {
        return false;
      }
    }
    return true;
  }
}
