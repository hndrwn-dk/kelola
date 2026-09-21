import 'package:flutter/services.dart';
import 'package:kelola/domain/shortcuts/os_shortcuts.dart';

class ShortcutsChannel {
  ShortcutsChannel({
    MethodChannel channel = const MethodChannel(
      'com.tursinalabs.kelola/shortcuts',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> set(List<OsShortcut> items) async {
    try {
      await _channel.invokeMethod<void>(
        'set',
        items.map((s) => s.toMap()).toList(),
      );
    } on MissingPluginException {
      // Tests and platforms without the native plugin.
    }
  }
}
