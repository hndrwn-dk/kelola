import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/sparkline.dart';

class DashCard extends StatelessWidget {
  const DashCard({
    super.key,
    required this.child,
    this.onTap,
    this.accent,
    this.padding = const EdgeInsets.fromLTRB(14, 14, 14, 14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final body = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x14FFFFFF)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accent != null)
                ColoredBox(
                  color: accent!,
                  child: const SizedBox(width: 4),
                ),
              Expanded(child: Padding(padding: padding, child: child)),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) {
      return body;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: body,
      ),
    );
  }
}

class FleetBars extends StatelessWidget {
  const FleetBars({super.key, required this.hosts});

  final List<Host> hosts;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    var healthy = 0;
    var warning = 0;
    var offline = 0;
    for (final h in hosts) {
      switch (h.attention) {
        case HostAttention.unreachable:
          offline++;
        case HostAttention.failedUnits:
        case HostAttention.diskHigh:
          warning++;
        case HostAttention.healthy:
        case HostAttention.unknown:
          healthy++;
      }
    }
    return Row(
      children: [
        _kpi(colors, 'Healthy', healthy, colors.green),
        const SizedBox(width: 8),
        _kpi(colors, 'Warning', warning, colors.amber),
        const SizedBox(width: 8),
        _kpi(colors, 'Offline', offline, colors.red),
      ],
    );
  }

  Widget _kpi(KelolaColors colors, String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: KelolaFonts.machine(color: colors.dim, size: 10)
                  .copyWith(letterSpacing: 0.1),
            ),
            const SizedBox(height: 6),
            Text(
              '$count',
              style: KelolaFonts.machine(
                color: color,
                size: 24,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArcGauge extends StatelessWidget {
  const ArcGauge({
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
    return DashCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
      child: SizedBox(
        height: 128,
        child: CustomPaint(
          painter: _ArcPainter(
            percent: p / 100,
            fill: fill,
            needle: colors.text,
          ),
          child: Align(
            alignment: const Alignment(0, 0.55),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: KelolaFonts.title(size: 22)),
                const SizedBox(height: 2),
                Text(
                  label.toUpperCase(),
                  style: KelolaFonts.machine(color: colors.dim, size: 10)
                      .copyWith(letterSpacing: 0.1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.percent,
    required this.fill,
    required this.needle,
  });

  final double percent;
  final Color fill;
  final Color needle;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.72);
    final radius = math.min(size.width * 0.42, size.height * 0.62);
    const start = math.pi;
    const sweep = math.pi;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = const Color(0x1AFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    final glowPaint = Paint()
      ..color = fill.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final fillPaint = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, start, sweep, false, trackPaint);
    if (percent > 0) {
      canvas.drawArc(rect, start, sweep * percent, false, glowPaint);
      canvas.drawArc(rect, start, sweep * percent, false, fillPaint);
    }

    final angle = start + sweep * percent;
    final inner = radius - 18;
    final outer = radius + 4;
    final needlePaint = Paint()
      ..color = needle
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(
        center.dx + math.cos(angle) * inner,
        center.dy + math.sin(angle) * inner,
      ),
      Offset(
        center.dx + math.cos(angle) * outer,
        center.dy + math.sin(angle) * outer,
      ),
      needlePaint,
    );
    canvas.drawCircle(center, 3.2, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.percent != percent ||
        oldDelegate.fill != fill;
  }
}

class CpuChartCard extends StatelessWidget {
  const CpuChartCard({
    super.key,
    required this.percent,
    required this.values,
    this.onTap,
  });

  final double percent;
  final List<double> values;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return DashCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CPU', style: KelolaFonts.eyebrow(colors)),
              const Spacer(),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: KelolaFonts.machine(
                  size: 18,
                  weight: FontWeight.w500,
                  color: colors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Sparkline(
            values: values.isEmpty ? const [0] : values,
            color: colors.amber,
            height: 56,
          ),
        ],
      ),
    );
  }
}

class LoadCard extends StatelessWidget {
  const LoadCard({
    super.key,
    required this.load,
    this.onTap,
  });

  final double load;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    return DashCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LOAD', style: KelolaFonts.eyebrow(colors)),
                const SizedBox(height: 4),
                Text(
                  load.toStringAsFixed(2),
                  style: KelolaFonts.title(size: 32),
                ),
              ],
            ),
          ),
          Text(
            '1 min',
            style: KelolaFonts.machine(color: colors.dim, size: 11),
          ),
        ],
      ),
    );
  }
}
