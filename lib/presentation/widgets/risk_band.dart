import 'package:flutter/material.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';

class RiskBand extends StatelessWidget {
  const RiskBand({
    super.key,
    required this.level,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.tone,
  });

  final RiskLevel level;
  final Widget child;
  final EdgeInsets padding;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final stripe = tone ?? colors.risk(level);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
              child: SizedBox(
                width: 6,
                child: level == RiskLevel.destructive && tone == null
                    ? const CustomPaint(painter: _HazardStripePainter())
                    : ColoredBox(color: stripe),
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

class _HazardStripePainter extends CustomPainter {
  const _HazardStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const stripe = 5.0;
    final dark = Paint()..color = KelolaColors.hazardDark;
    final red = Paint()..color = const Color(0xFFE5484D);
    canvas.drawRect(Offset.zero & size, dark);
    for (var x = -size.height; x < size.width + size.height; x += stripe * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + stripe, size.height)
        ..lineTo(x + stripe + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, red);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
