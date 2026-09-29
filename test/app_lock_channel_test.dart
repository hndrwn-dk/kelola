import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/app_lock/method_channel_app_lock.dart';

import 'app_lock_channel_support.dart';

void main() {
  const channel = MethodChannel('com.tursinalabs.kelola/app_lock');

  testWidgets('canAuthenticate and authenticate map channel replies', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'canAuthenticate') {
          return true;
        }
        if (call.method == 'authenticate') {
          return true;
        }
        if (call.method == 'setSecure') {
          return null;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        failOpenAppLockHandler,
      );
    });
    final port = MethodChannelAppLock(channel: channel);
    expect(await port.canAuthenticate(), isTrue);
    expect(await port.authenticate(), isTrue);
    await port.setRecentsSecure(true);
  });

  testWidgets('user cancel stays locked', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'authenticate') {
          return false;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        failOpenAppLockHandler,
      );
    });
    final port = MethodChannelAppLock(channel: channel);
    expect(await port.authenticate(), isFalse);
  });

  testWidgets('cancelled and unavailable platform errors stay locked', (
    tester,
  ) async {
    var code = 'cancelled';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw PlatformException(code: code, message: 'no');
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        failOpenAppLockHandler,
      );
    });
    final port = MethodChannelAppLock(channel: channel);
    expect(await port.authenticate(), isFalse);
    code = 'no_activity';
    expect(await port.authenticate(), isFalse);
    code = 'unavailable';
    expect(await port.authenticate(), isFalse);
    expect(await port.canAuthenticate(), isFalse);
  });

  testWidgets('missing plugin stays locked', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw MissingPluginException(call.method);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        failOpenAppLockHandler,
      );
    });
    final port = MethodChannelAppLock(channel: channel);
    expect(await port.canAuthenticate(), isFalse);
    expect(await port.authenticate(), isFalse);
    await port.setRecentsSecure(true);
  });
}
