import 'package:flutter/services.dart';
import 'package:kelola/data/fleet/fleet_watch_runner.dart';

abstract class FleetWatchBridge {
  Future<bool> requestPostNotifications();
  Future<void> notify(FleetWatchNotice notice);
  Future<void> schedule();
  Future<void> cancel();
  void setTickHandler(Future<void> Function()? handler);
}

class MethodChannelFleetWatchBridge implements FleetWatchBridge {
  MethodChannelFleetWatchBridge({
    MethodChannel channel = const MethodChannel('kelola/fleet_watch'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_onMethodCall);
  }

  final MethodChannel _channel;
  Future<void> Function()? _onTick;

  @override
  Future<bool> requestPostNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('requestPostNotifications') ??
          true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Future<void> notify(FleetWatchNotice notice) async {
    try {
      await _channel.invokeMethod<void>('notify', {
        'hostId': notice.hostId,
        'title': notice.title,
        'body': notice.body,
      });
    } on MissingPluginException {
      // Tests and desktop have no notifier.
    } on PlatformException {
      // Local notify is best-effort.
    }
  }

  @override
  Future<void> schedule() async {
    try {
      await _channel.invokeMethod<void>('schedule');
    } on MissingPluginException {
      // Tests and desktop have no worker.
    } on PlatformException {
      // Tests and desktop have no worker.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Best-effort.
    } on PlatformException {
      // Best-effort.
    }
  }

  @override
  void setTickHandler(Future<void> Function()? handler) {
    _onTick = handler;
  }

  Future<void> _onMethodCall(MethodCall call) async {
    if (call.method == 'tick') {
      await _onTick?.call();
    }
  }
}
