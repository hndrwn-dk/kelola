import 'package:flutter/services.dart';
import 'package:kelola/domain/widget/home_widget_snapshot.dart';

abstract class HomeWidgetBridge {
  Future<void> write(HomeWidgetSnapshot snap);
}

class MethodChannelHomeWidgetBridge implements HomeWidgetBridge {
  const MethodChannelHomeWidgetBridge();

  static const channel = MethodChannel('com.tursinalabs.kelola/widget');

  @override
  Future<void> write(HomeWidgetSnapshot snap) {
    return channel.invokeMethod<void>('update', snap.toMap());
  }
}
