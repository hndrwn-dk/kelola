import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';

class HostNavTile extends StatelessWidget {
  const HostNavTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return KelolaWorkRow(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Icon(Icons.chevron_right, color: colors.dim, size: 18),
    );
  }
}
