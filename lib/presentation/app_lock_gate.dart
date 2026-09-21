import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/app_lock/app_lock_timeout.dart';
import 'package:kelola/presentation/screens/app_lock_screen.dart';
import 'package:kelola/providers.dart';

class AppLockScope extends InheritedWidget {
  const AppLockScope({
    super.key,
    required this.locked,
    required this.enqueueLink,
    required super.child,
  });

  final bool locked;
  final void Function(String raw) enqueueLink;

  static AppLockScope? maybeOf(BuildContext context) {
    return context.getInheritedWidgetOfExactType<AppLockScope>();
  }

  @override
  bool updateShouldNotify(AppLockScope old) => locked != old.locked;
}

class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    required this.onUnlockedLink,
  });

  final Widget child;
  final Future<void> Function(String raw) onUnlockedLink;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _queue = AppLockLinkQueue();
  ProviderSubscription<AsyncValue<int>>? _timeoutSub;
  var _hydrated = false;
  var _loaded = false;
  var _locked = false;
  var _timeoutSec = 0;
  var _prompted = false;
  var _failOpenChecked = false;
  DateTime? _pausedAt;
  String? _notice;

  ProviderContainer? _container() {
    try {
      return ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated) {
      return;
    }
    _hydrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _hydrate();
      }
    });
  }

  void _hydrate() {
    _timeoutSub?.close();
    _timeoutSub = null;
    final container = _container();
    if (container == null || !container.exists(databaseProvider)) {
      return;
    }
    _timeoutSub = container.listen<AsyncValue<int>>(
      appLockTimeoutProvider,
      (previous, next) {
        final sec = next.asData?.value;
        if (sec != null) {
          _applyTimeout(sec);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _timeoutSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final shouldLock = shouldLockOnResume(
      timeoutSec: _timeoutSec,
      pausedAt: _pausedAt,
      now: DateTime.now(),
    );
    _pausedAt = null;
    if (shouldLock) {
      _lock();
    }
  }

  void _applyTimeout(int sec) {
    if (_loaded && sec == _timeoutSec) {
      return;
    }
    final first = !_loaded;
    final wasSecure = recentsSecure(_timeoutSec);
    _loaded = true;
    _timeoutSec = sec;
    final secure = recentsSecure(sec);
    final container = _container();
    if (container != null && (secure || wasSecure)) {
      container.read(appLockPortProvider).setRecentsSecure(secure);
    }
    if (sec == 0) {
      if (_locked) {
        _unlock();
      }
      return;
    }
    if (first && lockOnColdStart(sec)) {
      _lock();
    }
  }

  void _lock() {
    _failOpenChecked = false;
    _prompted = false;
    if (!mounted) {
      _locked = true;
      return;
    }
    setState(() {
      _locked = true;
    });
  }

  void _unlock() {
    if (!mounted) {
      _locked = false;
      return;
    }
    setState(() {
      _locked = false;
    });
    final raw = _queue.take();
    if (raw != null) {
      widget.onUnlockedLink(raw);
    }
  }

  Future<void> _failOpenIfNeeded() async {
    if (_failOpenChecked || !_locked) {
      return;
    }
    _failOpenChecked = true;
    final container = _container();
    if (container == null) {
      _unlock();
      return;
    }
    final ok = await container.read(appLockPortProvider).canAuthenticate();
    if (!mounted || ok || _timeoutSec == 0) {
      return;
    }
    setState(() {
      _locked = false;
      _notice = 'Device screen lock is off. Inventory is open.';
    });
    final raw = _queue.take();
    if (raw != null) {
      await widget.onUnlockedLink(raw);
    }
  }

  Future<void> _authenticate() async {
    final container = _container();
    if (container == null) {
      _unlock();
      return;
    }
    final ok = await container.read(appLockPortProvider).authenticate();
    if (!mounted || !ok) {
      return;
    }
    _unlock();
  }

  void _enqueue(String raw) {
    _queue.enqueue(raw);
  }

  @override
  Widget build(BuildContext context) {
    if (_locked && !_prompted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || !_locked || _prompted) {
          return;
        }
        _prompted = true;
        await _failOpenIfNeeded();
        if (!mounted || !_locked) {
          return;
        }
        await _authenticate();
      });
    }
    return AppLockScope(
      locked: _locked,
      enqueueLink: _enqueue,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: _locked, child: widget.child),
          if (_locked)
            AppLockScreen(
              onUnlock: () {
                _authenticate();
              },
              notice: _notice,
            ),
          if (!_locked && _notice != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: kelolaScrollPadding(context, left: 16, right: 16),
                child: Text(
                  _notice!,
                  textAlign: TextAlign.center,
                  style: KelolaType.body(color: context.kc.muted, size: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
