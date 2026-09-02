/// Consecutive-failure backoff for SSH poll loops.
class PollBackoff {
  PollBackoff({
    this.maxFailures = 5,
    this.base = const Duration(seconds: 5),
  });

  final int maxFailures;
  final Duration base;
  int consecutiveFailures = 0;

  bool get stopped => consecutiveFailures >= maxFailures;

  bool get disconnected => consecutiveFailures > 0;

  void success() {
    consecutiveFailures = 0;
  }

  /// Records a failure. Returns the next delay, or null when polling must stop.
  Duration? failure() {
    consecutiveFailures++;
    if (consecutiveFailures >= maxFailures) {
      return null;
    }
    return base * (1 << (consecutiveFailures - 1));
  }
}

String metricsPollKicker({
  required Duration? poll,
  required bool disconnected,
}) {
  if (disconnected) {
    return 'DISCONNECTED';
  }
  if (poll == null) {
    return 'PAUSED';
  }
  return 'POLLING · ${poll.inSeconds}S';
}
