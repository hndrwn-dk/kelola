import 'package:flutter/material.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class StatMeter extends StatelessWidget {
  const StatMeter({
    super.key,
    required this.label,
    required this.value,
    required this.percent,
    this.onTap,
  });

  final String label;
  final String value;
  final double percent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final p = percent.clamp(0, 100);
    final fill = p >= 90
        ? colors.red
        : p >= 75
            ? colors.amber
            : colors.green;
    final child = Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label.toUpperCase(),
                style: KelolaFonts.machine(color: colors.dim, size: 9).copyWith(
                  letterSpacing: 0.09,
                ),
              ),
              if (onTap != null) ...[
                const Spacer(),
                Icon(Icons.chevron_right, size: 16, color: colors.dim),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: KelolaFonts.title(size: 22)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                children: [
                  ColoredBox(color: colors.surface3, child: const SizedBox.expand()),
                  FractionallySizedBox(
                    widthFactor: p / 100,
                    child: ColoredBox(color: fill, child: const SizedBox.expand()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: child,
    );
  }
}

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: alert ? colors.red.withValues(alpha: 0.5) : colors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: KelolaFonts.title(size: 14)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KelolaFonts.machine(
                    color: alert ? colors.red : colors.dim,
                    size: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
