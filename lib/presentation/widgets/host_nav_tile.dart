import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        tileColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.line),
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: colors.dim, fontSize: 12),
        ),
        trailing: Icon(Icons.chevron_right, color: colors.dim),
        onTap: onTap,
      ),
    );
  }
}
