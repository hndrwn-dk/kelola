import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class RiskBand extends StatelessWidget {
  const RiskBand({
    super.key,
    required this.level,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final RiskLevel level;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: colors.risk(level),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Padding(padding: padding, child: child),
            ),
          ],
        ),
      ),
    );
  }
}
