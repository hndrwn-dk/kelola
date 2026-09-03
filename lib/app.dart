import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/screens/boot_gate.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart' as legacy;

final kelolaNavigatorKey = GlobalKey<NavigatorState>();

class KelolaApp extends StatefulWidget {
  const KelolaApp({super.key, this.home});

  final Widget? home;

  @override
  State<KelolaApp> createState() => _KelolaAppState();
}

class _KelolaAppState extends State<KelolaApp> {
  static const _links = MethodChannel('com.tursinalabs.kelola/links');

  /// Design-system theme, plus the pre-retrofit [legacy.KelolaColors]
  /// extension so unmigrated screens keep resolving colors until Phase 3.
  ThemeData _theme() {
    return buildKelolaDarkTheme().copyWith(
      extensions: const [
        KelolaColors.dark,
        legacy.KelolaColors.dark,
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _links.setMethodCallHandler((call) async {
      if (call.method == 'opened' && call.arguments is String) {
        _openLink(call.arguments as String);
      }
    });
  }

  @override
  void dispose() {
    _links.setMethodCallHandler(null);
    super.dispose();
  }

  void _openLink(String raw) {
    final link = parseKelolaLink(raw);
    final id = link.hostId;
    if (id == null || id.isEmpty) {
      return;
    }
    kelolaNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => HostDashboardScreen(
          hostId: id,
          openIncident: link.incident,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    final ink = KelolaColors.dark.ink;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: ink,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MaterialApp(
        navigatorKey: kelolaNavigatorKey,
        title: 'Kelola',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        home: widget.home ?? const BootGate(),
      ),
    );
  }
}
