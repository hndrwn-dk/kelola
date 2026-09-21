import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/keystore/method_channel_hardware_signer.dart';

void main() {
  const channel = MethodChannel('com.tursinalabs.kelola/hardware_signer');

  Future<List<String>> mockHaptics(WidgetTester tester) async {
    final types = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          types.add(call.arguments as String);
        }
        return null;
      },
    );
    return types;
  }

  testWidgets('light haptic after successful confirmPresence and sign',
      (tester) async {
    final types = await mockHaptics(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'confirmPresence') {
          return null;
        }
        if (call.method == 'sign') {
          return <int>[1, 2, 3];
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final signer = MethodChannelHardwareSigner(channel: channel);
    await signer.confirmPresence();
    expect(types, ['HapticFeedbackType.lightImpact']);
    await signer.sign('kelola', Uint8List(0));
    expect(types, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.lightImpact',
    ]);
  });

  testWidgets('failed confirmPresence does not haptic', (tester) async {
    final types = await mockHaptics(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw PlatformException(code: 'auth_failed', message: 'no');
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    final signer = MethodChannelHardwareSigner(channel: channel);
    await expectLater(
      signer.confirmPresence(),
      throwsA(isA<PlatformException>()),
    );
    expect(types, isEmpty);
  });
}
