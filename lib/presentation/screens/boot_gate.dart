import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

class BootGate extends ConsumerStatefulWidget {
  const BootGate({super.key});

  @override
  ConsumerState<BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<BootGate> {
  String? _hostId;
  var _incident = false;
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
    if (!mounted) {
      return;
    }
    setState(() {
      _hostId = link.hostId;
      _incident = link.incident;
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
    final id = _hostId;
    if (id == null || id.isEmpty) {
      return const HostsScreen();
    }
    return HostDashboardScreen(hostId: id, openIncident: _incident);
  }
}
