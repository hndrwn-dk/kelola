import 'package:kelola/domain/keep_awake/keep_awake.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class WakelockPlusPort implements WakelockPort {
  @override
  Future<void> setEnabled(bool enabled) {
    return enabled ? WakelockPlus.enable() : WakelockPlus.disable();
  }
}
