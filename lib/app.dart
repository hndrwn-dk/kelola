import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/presentation/screens/boot_gate.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart' as legacy;

class KelolaApp extends StatelessWidget {
  const KelolaApp({super.key, this.home});

  final Widget? home;

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
        title: 'Kelola',
        debugShowCheckedModeBanner: false,
        theme: theme,
        darkTheme: theme,
        themeMode: ThemeMode.dark,
        home: home ?? const BootGate(),
      ),
    );
  }
}
