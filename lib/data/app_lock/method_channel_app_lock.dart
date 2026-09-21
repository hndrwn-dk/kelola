import 'package:flutter/services.dart';
import 'package:kelola/data/app_lock/app_lock_port.dart';

class MethodChannelAppLock implements AppLockPort {
  MethodChannelAppLock({
    MethodChannel channel = const MethodChannel(
      'com.tursinalabs.kelola/app_lock',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<bool> canAuthenticate() async {
    try {
      return await _channel.invokeMethod<bool>('canAuthenticate') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _channel.invokeMethod<bool>('authenticate') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'cancelled' || e.code == 'auth_failed') {
        return false;
      }
      return true;
    }
  }

  @override
  Future<void> setRecentsSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
