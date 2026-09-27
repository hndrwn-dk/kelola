import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/providers.dart';

class FleetWatchResume extends ConsumerStatefulWidget {
  const FleetWatchResume({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FleetWatchResume> createState() => _FleetWatchResumeState();
}

class _FleetWatchResumeState extends ConsumerState<FleetWatchResume> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onResume: _onResume);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _onResume();
      }
    });
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onResume() {
    ref.read(fleetWatchControllerProvider).maybeTick();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
