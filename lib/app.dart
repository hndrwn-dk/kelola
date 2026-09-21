import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/kelola_link_open.dart';
import 'package:kelola/presentation/screens/boot_gate.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart' as legacy;
import 'package:kelola/providers.dart';

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
        await _openLink(call.arguments as String);
      }
    });
  }

  @override
  void dispose() {
    _links.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _openLink(String raw) async {
    final nav = kelolaNavigatorKey.currentState;
    final context = kelolaNavigatorKey.currentContext;
    if (nav == null || context == null || !context.mounted) {
      return;
    }
    final repo = ProviderScope.containerOf(context).read(hostRepositoryProvider);
    final dash = await dashboardForLink(repo, parseKelolaLink(raw));
    if (dash == null || !nav.mounted) {
      return;
    }
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => dash,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
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
