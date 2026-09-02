import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final fromLink = _hostIdFromRoute(
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _hostId = fromLink;
      _ready = true;
    });
  }

  static String? _hostIdFromRoute(String name) {
    final uri = Uri.tryParse(name);
    if (uri == null) {
      return null;
    }
    if (uri.scheme == 'kelola' &&
        uri.host == 'host' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    final parts = name.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2 && parts.first == 'host') {
      return parts[1];
    }
    return null;
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
    return HostDashboardScreen(hostId: id);
  }
}
