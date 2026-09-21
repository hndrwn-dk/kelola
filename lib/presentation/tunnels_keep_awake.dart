import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/keep_awake/keep_awake.dart';
import 'package:kelola/providers.dart';

class TunnelsKeepAwake extends ConsumerStatefulWidget {
  const TunnelsKeepAwake({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TunnelsKeepAwake> createState() => _TunnelsKeepAwakeState();
}

class _TunnelsKeepAwakeState extends ConsumerState<TunnelsKeepAwake> {
  var _held = false;
  late final KeepAwake _keepAwake;

  @override
  void initState() {
    super.initState();
    _keepAwake = ref.read(keepAwakeProvider);
  }

  @override
  void dispose() {
    unawaited(_keepAwake.release('tunnels'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tunnels = ref.watch(activeTunnelsProvider).valueOrNull ?? const [];
    final shouldHold = tunnels.isNotEmpty;
    if (shouldHold != _held) {
      _held = shouldHold;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(
          shouldHold ? _keepAwake.acquire('tunnels') : _keepAwake.release('tunnels'),
        );
      });
    }
    return widget.child;
  }
}
