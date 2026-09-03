import 'dart:async';

/// UI countdown for the Keep window. Rollback itself is scheduled on the
/// host inside [FirewallApplyProbe] (firewalld --timeout or nohup sleep)
/// before the rule changes. This timer must not be the safety net.
class FirewallAutoRevert {
  FirewallAutoRevert({
    required this.apply,
    required this.onExpired,
    this.window = const Duration(seconds: 60),
  });

  static const defaultWindow = Duration(seconds: 60);

  final Future<void> Function() apply;
  final Future<void> Function() onExpired;
  final Duration window;

  Timer? _timer;
  Completer<bool>? _done;
  bool _settled = false;

  bool confirmed = false;
  bool expired = false;

  bool get isPending => _done != null && !_done!.isCompleted;

  Future<bool> start() async {
    if (_done != null) {
      return _done!.future;
    }
    _done = Completer<bool>();
    try {
      await apply();
    } catch (e, st) {
      _settled = true;
      _done!.completeError(e, st);
      rethrow;
    }
    if (_settled) {
      return _done!.future;
    }
    _timer = Timer(window, () {
      unawaited(_expire());
    });
    return _done!.future;
  }

  void confirm() {
    if (_settled || confirmed) {
      return;
    }
    confirmed = true;
    _timer?.cancel();
    _settle(true);
  }

  Future<void> _expire() async {
    if (_settled || confirmed) {
      return;
    }
    _settled = true;
    expired = true;
    await onExpired();
    _complete(false);
  }

  void _settle(bool kept) {
    _settled = true;
    _timer?.cancel();
    _complete(kept);
  }

  void _complete(bool kept) {
    final done = _done;
    if (done != null && !done.isCompleted) {
      done.complete(kept);
    }
  }

  void dispose() {
    _timer?.cancel();
    if (_done != null && !_done!.isCompleted) {
      _done!.complete(confirmed);
    }
  }
}
