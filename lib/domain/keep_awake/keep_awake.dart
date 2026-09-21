abstract class WakelockPort {
  Future<void> setEnabled(bool enabled);
}

class KeepAwake {
  KeepAwake(this._port);

  final WakelockPort _port;
  final Set<String> _holds = {};

  Future<void> acquire(String token) async {
    if (!_holds.add(token)) {
      return;
    }
    if (_holds.length == 1) {
      await _set(true);
    }
  }

  Future<void> release(String token) async {
    if (!_holds.remove(token)) {
      return;
    }
    if (_holds.isEmpty) {
      await _set(false);
    }
  }

  Future<void> _set(bool enabled) async {
    try {
      await _port.setEnabled(enabled);
    } catch (_) {}
  }
}
