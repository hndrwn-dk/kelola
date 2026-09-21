import 'package:flutter/services.dart';

const appLockTestChannel = MethodChannel('com.tursinalabs.kelola/app_lock');

Future<Object?>? failOpenAppLockHandler(MethodCall call) async {
  switch (call.method) {
    case 'canAuthenticate':
      return false;
    case 'authenticate':
      return true;
    default:
      return null;
  }
}
