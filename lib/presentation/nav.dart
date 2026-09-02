import 'package:flutter/material.dart';
import 'package:kelola/presentation/screens/hosts_screen.dart';

void openHostsRoot(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const HostsScreen()),
    (route) => false,
  );
}
