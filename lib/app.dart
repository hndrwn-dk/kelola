import 'package:flutter/material.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class KelolaApp extends StatelessWidget {
  const KelolaApp({super.key, this.home});

  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kelola',
      debugShowCheckedModeBanner: false,
      theme: kelolaTheme(),
      home: home ?? const HostsScreen(),
    );
  }
}
