import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/kelola_link_open.dart';
import 'package:kelola/presentation/os_shortcut_sync.dart';
import 'package:kelola/presentation/tunnels_keep_awake.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

class BootGate extends ConsumerStatefulWidget {
  const BootGate({super.key});

  @override
  ConsumerState<BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<BootGate> {
  Widget? _home;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final link = parseKelolaLink(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    final dash = await dashboardForLink(
      ref.read(hostRepositoryProvider),
      link,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _home = dash ?? const HostsScreen();
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: KelolaSpinner()),
      );
    }
    return TunnelsKeepAwake(
      child: OsShortcutSync(child: _home ?? const HostsScreen()),
    );
  }
}
