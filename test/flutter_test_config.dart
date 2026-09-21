import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'app_lock_channel_support.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(appLockTestChannel, failOpenAppLockHandler);
  await testMain();
}
