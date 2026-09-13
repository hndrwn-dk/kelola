import 'dart:async';

import 'package:flutter/services.dart';
import 'package:kelola/domain/tunnels/active_tunnel.dart';

typedef TunnelNativeHandler = Future<void> Function(TunnelNativeEvent event);

enum TunnelNativeEvent {
  stopAll,
  taskRemoved,
}

/// Dart ↔ Android MethodChannel for the tunnel foreground service.
abstract class TunnelBridge {
  Future<void> start({required String text});
  Future<void> update({required String text});
  Future<void> stop();

  /// Requests POST_NOTIFICATIONS on API 33+. Returns whether notifications
  /// are (or remain) allowed. Does not block tunnel start when denied.
  Future<bool> requestPostNotifications();

  /// Opens the system notification settings for this app.
  Future<void> openNotificationSettings();

  void setNativeHandler(TunnelNativeHandler? handler);
}

class MethodChannelTunnelBridge implements TunnelBridge {
  MethodChannelTunnelBridge({
    MethodChannel channel = const MethodChannel('kelola/tunnels'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;
  TunnelNativeHandler? _handler;

  @override
  Future<void> start({required String text}) async {
    try {
      await _channel.invokeMethod<void>('start', {'text': text});
    } on PlatformException {
      // Native start can fail if the activity is gone; do not crash Dart.
    }
  }

  @override
  Future<void> update({required String text}) async {
    try {
      await _channel.invokeMethod<void>('update', {'text': text});
    } on PlatformException {
      // Defensive: Android 12+ may reject background FGS starts; update path
      // should never take down the isolate when notify fails.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Best-effort stop.
    }
  }

  @override
  Future<bool> requestPostNotifications() async {
    return await _channel.invokeMethod<bool>('requestPostNotifications') ??
        true;
  }

  @override
  Future<void> openNotificationSettings() {
    return _channel.invokeMethod<void>('openNotificationSettings');
  }

  @override
  void setNativeHandler(TunnelNativeHandler? handler) {
    _handler = handler;
  }

  Future<void> _onMethodCall(MethodCall call) async {
    final handler = _handler;
    if (handler == null) return;
    switch (call.method) {
      case 'stopAll':
        await handler(TunnelNativeEvent.stopAll);
      case 'taskRemoved':
        await handler(TunnelNativeEvent.taskRemoved);
    }
  }
}

/// Whether a tunnel should keep the FGS notification alive.
bool tunnelKeepsFgsAlive(ActiveTunnel tunnel) {
  switch (tunnel.state) {
    case TunnelState.starting:
    case TunnelState.listening:
    case TunnelState.idleClosing:
    case TunnelState.closing:
      return true;
    case TunnelState.failed:
    case TunnelState.closed:
      return false;
  }
}

/// Notification body: `{n} tunnel(s) active · {aliases}` plus optional countdown.
String formatTunnelNotificationText(
  List<ActiveTunnel> tunnels, {
  DateTime? now,
}) {
  final live = tunnels.where(tunnelKeepsFgsAlive).toList(growable: false);
  if (live.isEmpty) return '';

  final n = live.length;
  final noun = n == 1 ? 'tunnel' : 'tunnels';
  final aliases = <String>[];
  for (final t in live) {
    if (!aliases.contains(t.hostAlias)) aliases.add(t.hostAlias);
  }
  var text = '$n $noun active · ${aliases.join(', ')}';

  final closing = live.where(
    (t) => t.state == TunnelState.idleClosing && t.closesAtUtc != null,
  );
  if (closing.isNotEmpty) {
    final clock = now ?? DateTime.now().toUtc();
    final soonest = closing
        .map((t) => t.closesAtUtc!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final secs = soonest.difference(clock).inSeconds;
    final remaining = secs < 0 ? 0 : secs;
    text = '$text · closes in ${remaining}s';
  }
  return text;
}

/// Mirrors [TunnelManager.watch] onto [TunnelBridge] start/update/stop.
class TunnelFgsSync {
  TunnelFgsSync({
    required TunnelBridge bridge,
    required Stream<List<ActiveTunnel>> tunnels,
    DateTime Function()? clock,
    Duration countdownTick = const Duration(seconds: 1),
  })  : _bridge = bridge,
        _tunnels = tunnels,
        _clock = clock ?? _utcNow,
        _countdownTick = countdownTick;

  final TunnelBridge _bridge;
  final Stream<List<ActiveTunnel>> _tunnels;
  final DateTime Function() _clock;
  final Duration _countdownTick;

  StreamSubscription<List<ActiveTunnel>>? _sub;
  Timer? _countdownTimer;
  List<ActiveTunnel> _lastLive = const [];
  bool _running = false;
  String? _lastText;

  static DateTime _utcNow() => DateTime.now().toUtc();

  void attach() {
    _sub ??= _tunnels.listen(_onTunnels);
  }

  Future<void> dispose() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onTunnels(List<ActiveTunnel> tunnels) async {
    final live = tunnels.where(tunnelKeepsFgsAlive).toList(growable: false);
    _lastLive = live;
    if (live.isEmpty) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      if (_running) {
        _running = false;
        _lastText = null;
        await _bridge.stop();
      }
      return;
    }

    _syncCountdownTimer(live);
    await _pushText(live);
  }

  void _syncCountdownTimer(List<ActiveTunnel> live) {
    final needsTick = live.any(
      (t) => t.state == TunnelState.idleClosing && t.closesAtUtc != null,
    );
    if (!needsTick) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
      return;
    }
    _countdownTimer ??= Timer.periodic(_countdownTick, (_) {
      unawaited(_pushText(_lastLive));
    });
  }

  Future<void> _pushText(List<ActiveTunnel> live) async {
    if (live.isEmpty) return;
    final text = formatTunnelNotificationText(live, now: _clock());
    if (!_running) {
      _running = true;
      _lastText = text;
      await _bridge.start(text: text);
      return;
    }
    if (text == _lastText) return;
    _lastText = text;
    await _bridge.update(text: text);
  }
}
