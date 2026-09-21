enum AppLockTimeout {
  off(0, 'Off'),
  immediately(-1, 'Immediately'),
  oneMinute(60, '1 minute'),
  fiveMinutes(300, '5 minutes'),
  fifteenMinutes(900, '15 minutes');

  const AppLockTimeout(this.seconds, this.label);

  final int seconds;
  final String label;

  static AppLockTimeout fromSeconds(int seconds) {
    for (final value in AppLockTimeout.values) {
      if (value.seconds == seconds) {
        return value;
      }
    }
    return AppLockTimeout.off;
  }
}

bool shouldLockOnResume({
  required int timeoutSec,
  required DateTime? pausedAt,
  required DateTime now,
}) {
  final timeout = AppLockTimeout.fromSeconds(timeoutSec);
  if (timeout == AppLockTimeout.off) {
    return false;
  }
  if (pausedAt == null) {
    return false;
  }
  if (timeout == AppLockTimeout.immediately) {
    return true;
  }
  return !now.difference(pausedAt).isNegative &&
      now.difference(pausedAt) >= Duration(seconds: timeout.seconds);
}

bool lockOnColdStart(int timeoutSec) {
  return AppLockTimeout.fromSeconds(timeoutSec) != AppLockTimeout.off;
}

bool recentsSecure(int timeoutSec) {
  return AppLockTimeout.fromSeconds(timeoutSec) != AppLockTimeout.off;
}

class AppLockLinkQueue {
  String? _pending;

  void enqueue(String raw) {
    _pending = raw;
  }

  String? take() {
    final value = _pending;
    _pending = null;
    return value;
  }
}
