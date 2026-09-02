import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kelola/domain/hosts/dashboard_status.dart';
import 'package:kelola/domain/hosts/os_icon_kind.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'kelola_theme.dart';

/// The signature element. A card with a colored left edge encoding
/// RiskLevel. Destructive gets a diagonal hazard stripe, not a flat
/// red bar — that's the one place the UI is allowed to be loud.
///
/// THIS is what "risk band" means. If a screen shows a service,
/// a firewall rule, a package update, or any mutating action, it
/// goes inside a RiskBand. It is never a plain Card, never a
/// Material ListTile, never a gauge, never a FAB.
class RiskBand extends StatelessWidget {
  final RiskLevel risk;
  final HealthStatus? status;
  final Widget child;
  final EdgeInsets padding;

  const RiskBand({
    super.key,
    required this.risk,
    this.status,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(15, 11, 12, 11),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final bandColor =
        status != null ? c.forHealth(status!) : c.forRisk(risk);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line, width: 1),
        borderRadius: BorderRadius.circular(KelolaRadii.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ClipRect(
              child: risk == RiskLevel.destructive
                  ? CustomPaint(
                      painter: _HazardStripePainter(
                        bright: c.red,
                        dark: c.redDim,
                      ),
                      child: const SizedBox.expand(),
                    )
                  : ColoredBox(color: bandColor),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class _HazardStripePainter extends CustomPainter {
  _HazardStripePainter({required this.bright, required this.dark});

  final Color bright;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    paintHazardStripe(canvas, size, bright, dark);
  }

  @override
  bool shouldRepaint(covariant _HazardStripePainter oldDelegate) =>
      oldDelegate.bright != bright || oldDelegate.dark != dark;
}

void paintHazardStripe(Canvas canvas, Size size, Color bright, Color dark) {
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  const stripeWidth = 5.0;
  canvas.drawRect(Offset.zero & size, Paint()..color = dark);
  final path = Path();
  for (double x = -size.height;
      x < size.width + size.height;
      x += stripeWidth * 2) {
    path.addPolygon([
      Offset(x, 0),
      Offset(x + stripeWidth, 0),
      Offset(x + stripeWidth + size.height, size.height),
      Offset(x + size.height, size.height),
    ], true);
  }
  canvas.drawPath(path, Paint()..color = bright);
  canvas.restore();
}

/// A 2-up stat tile — LOAD, MEMORY, DISK, FAILED. No gauges, no
/// dials. A label in mono, a big display-weight number, and an
/// optional thin meter bar underneath.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final double? meterFraction; // 0..1, omit to hide the bar
  final HealthStatus? status;
  final RiskLevel meterRisk;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.meterFraction,
    this.status,
    this.meterRisk = RiskLevel.read,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KelolaRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              text: value,
              style: KelolaType.display(color: c.text, size: 22, weight: FontWeight.w600),
              children: unit == null
                  ? null
                  : [
                      TextSpan(
                        text: ' $unit',
                        style: KelolaType.body(color: c.muted, size: 11),
                      ),
                    ],
            ),
          ),
          if (meterFraction != null) ...[
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: meterFraction!.clamp(0, 1),
                  backgroundColor: c.surface3,
                  color: status != null
                      ? c.forHealth(status!)
                      : c.forRisk(meterRisk),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 2-up / 3-up tool shortcut on S06. Border + surface, never a
/// plain filled box. Title is human (display); the sub-label is
/// machine (mono).
class ToolTile extends StatelessWidget {
  final String label;
  final String meta;
  final VoidCallback onTap;

  const ToolTile({
    super.key,
    required this.label,
    required this.meta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KelolaRadii.sm),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KelolaRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KelolaType.display(color: c.text, size: 12),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KelolaType.mono(color: c.muted, size: 9.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single row inside a RiskBand: optional status dot from HealthStatus
/// (object rows only — action rows omit [status] and get no dot), name
/// (display font), meta line (mono — it came from the server),
/// optional trailing pill colored by the action's RiskLevel.
class ServiceRow extends StatelessWidget {
  final RiskLevel risk;
  final HealthStatus? status;
  final String name;
  final String meta;
  final String? pillText;
  final HealthStatus? pillStatus;
  final String? endValue;
  final String? endMeta;
  final Widget? leading;
  final String? detail;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ServiceRow({
    super.key,
    required this.risk,
    this.status,
    required this.name,
    required this.meta,
    this.pillText,
    this.pillStatus,
    this.endValue,
    this.endMeta,
    this.leading,
    this.detail,
    this.compact = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final health = status != null ? c.forHealth(status!) : c.forRisk(risk);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: RiskBand(
        risk: risk,
        status: status,
        padding: compact
            ? const EdgeInsets.fromLTRB(12, 6, 10, 6)
            : const EdgeInsets.fromLTRB(15, 11, 12, 11),
        child: Row(
          children: [
            if (status != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: health, shape: BoxShape.circle),
              ),
              const SizedBox(width: 9),
            ],
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KelolaType.display(
                        color: c.text,
                        size: compact ? 12.5 : 13,
                      )),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KelolaType.mono(
                        color: c.muted,
                        size: compact ? 10 : 11,
                      ).copyWith(height: compact ? 1.25 : null)),
                  if (detail != null)
                    Text(detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KelolaType.mono(
                          color: c.muted,
                          size: compact ? 10 : 11,
                        ).copyWith(height: compact ? 1.25 : null)),
                ],
              ),
            ),
            if (endValue != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    endValue!,
                    style: KelolaType.display(
                      color: status != null ? health : c.text,
                      size: 13,
                    ),
                  ),
                  if (endMeta != null)
                    Text(
                      endMeta!,
                      style: KelolaType.mono(color: c.muted, size: 11),
                    ),
                ],
              ),
            ],
            if (pillText != null) ...[
              const SizedBox(width: 8),
              _Pill(
                text: pillText!,
                risk: risk,
                status: pillStatus,
                dim: status == HealthStatus.unknown,
              ),
            ],
            if (onTap != null && endValue == null) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 16, color: c.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final RiskLevel risk;
  final HealthStatus? status;
  final bool dim;
  const _Pill({
    required this.text,
    required this.risk,
    this.status,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final color = status != null ? c.forHealth(status!) : c.forRisk(risk);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text.toUpperCase(),
          style: KelolaType.mono(color: color, size: 8.5, letterSpacing: 0.6)),
    );
    if (!dim) {
      return pill;
    }
    return Opacity(opacity: 0.55, child: pill);
  }
}

/// Compact filter chip for list screens (S08 Failed / Running / Enabled / All).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final on = selected && enabled;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: on ? c.amber : null,
        border: Border.all(color: on ? c.amber : c.line),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: KelolaType.mono(
          color: enabled ? (on ? c.ink : c.muted) : c.dim,
          size: 8.5,
          letterSpacing: 0.6,
          weight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: pill,
      ),
    );
  }
}

/// Single-confirmation mutate dialog. Destructive actions must not
/// use this — they go through [DestructiveConfirmSheet].
class MutateConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  const MutateConfirmDialog({
    super.key,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.onCancel,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(KelolaRadii.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: KelolaType.display(color: c.text, size: 17)),
          const SizedBox(height: 8),
          Text(body, style: KelolaType.body(color: c.muted, size: 13)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: Text(
                    'Cancel',
                    style: KelolaType.display(color: c.muted, size: 13),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.amber,
                    foregroundColor: c.ink,
                  ),
                  child: Text(
                    confirmLabel,
                    style: KelolaType.display(color: c.ink, size: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<bool> showMutateConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: MutateConfirmDialog(
          title: title,
          body: body,
          confirmLabel: confirmLabel,
          onCancel: () => Navigator.of(ctx).pop(false),
          onConfirm: () => Navigator.of(ctx).pop(true),
        ),
      );
    },
  );
  return ok == true;
}

/// One journal line. Timestamp is dim mono; the message color is
/// error / warning / muted info — never green, never a second accent.
class JournalLogLine extends StatelessWidget {
  final String timestamp;
  final String message;
  final JournalLineKind kind;

  const JournalLogLine({
    super.key,
    required this.timestamp,
    required this.message,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final (bar, fg, wash) = switch (kind) {
      JournalLineKind.error => (c.red, c.red, c.red.withValues(alpha: 0.055)),
      JournalLineKind.warning => (c.amber, c.amber, c.amber.withValues(alpha: 0.05)),
      JournalLineKind.info => (c.line, c.muted, null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: wash,
        border: Border(left: BorderSide(color: bar, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: timestamp,
                style: KelolaType.mono(color: c.dim, size: 9),
              ),
              TextSpan(
                text: '  $message',
                style: KelolaType.mono(color: fg, size: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum JournalLineKind { error, warning, info }

/// Thin polyline trend — CPU/mem/network over time. No axes, no
/// gridlines, no third-party chart package. This is deliberately
/// minimal; do not let it grow into a full chart widget.
class Sparkline extends StatelessWidget {
  final List<double> values; // pre-normalized 0..1
  final Color color;
  final double height;

  const Sparkline({super.key, required this.values, required this.color, this.height = 34});

  @override
  Widget build(BuildContext context) {
    final pts = values.length == 1 ? [values.first, values.first] : values;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(pts, color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - values[i].clamp(0, 1));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

/// Destructive confirmation sheet — hazard-striped top edge, plain
/// statement of consequence, type-to-confirm gate. This is the ONLY
/// pattern for any RiskLevel.destructive action. Never a plain
/// AlertDialog for these.
class DestructiveConfirmSheet extends StatefulWidget {
  final String title;
  final String consequence;
  final String warning;
  final String confirmToken; // e.g. the hostname
  final VoidCallback onConfirmed;

  const DestructiveConfirmSheet({
    super.key,
    required this.title,
    required this.consequence,
    required this.warning,
    required this.confirmToken,
    required this.onConfirmed,
  });

  @override
  State<DestructiveConfirmSheet> createState() => _DestructiveConfirmSheetState();
}

class _DestructiveConfirmSheetState extends State<DestructiveConfirmSheet> {
  final _controller = TextEditingController();
  bool get _match => _controller.text.trim() == widget.confirmToken;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(KelolaRadii.lg)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 4,
            child: CustomPaint(
              painter: _HazardStripePainter(bright: c.red, dark: c.redDim),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 14),
          Text(widget.title, style: KelolaType.display(color: c.text, size: 17)),
          const SizedBox(height: 7),
          Text(widget.consequence, style: KelolaType.body(color: c.muted, size: 12)),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.red.withOpacity(0.08),
              border: Border.all(color: c.redDim),
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
            ),
            child: Text(widget.warning,
                style: KelolaType.mono(color: const Color(0xFFF2A9AB), size: 10)),
          ),
          const SizedBox(height: 13),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Type ',
                  style: KelolaType.body(color: c.text),
                ),
                TextSpan(
                  text: widget.confirmToken,
                  style: KelolaType.mono(color: c.amber, size: 15),
                ),
                TextSpan(
                  text: ' to confirm',
                  style: KelolaType.body(color: c.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            style: KelolaType.mono(color: c.text, size: 12),
            decoration: InputDecoration(
              hintText: widget.confirmToken,
              hintStyle: KelolaType.mono(color: c.dim, size: 12),
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KelolaRadii.sm),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(KelolaRadii.sm),
                borderSide: BorderSide(color: c.amber),
              ),
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton(
                  onPressed: _match
                      ? () {
                          Navigator.pop(context);
                          widget.onConfirmed();
                        }
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: c.red),
                  child: const Text('Confirm'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Human mode label in the AppBar kicker — display type, never mono.
class ModePill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const ModePill({
    super.key,
    required this.label,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: active ? c.amber : null,
        border: Border.all(color: c.amber),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: KelolaType.display(
          color: active ? c.ink : c.amber,
          size: 10,
          weight: FontWeight.w600,
        ),
      ),
    );
    if (onTap == null) {
      return pill;
    }
    return GestureDetector(onTap: onTap, child: pill);
  }
}

/// Labeled field. Labels are human (body). Values are display for names
/// Kelola wrote, or mono when the string is an address, user, port, or path.
class KelolaInput extends StatelessWidget {
  const KelolaInput({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.mono = false,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool mono;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final valueStyle = mono
        ? KelolaType.mono(color: c.text, size: 13)
        : KelolaType.display(color: c.text, size: 15);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: KelolaType.body(color: c.muted, size: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: valueStyle,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: (mono
                    ? KelolaType.mono(color: c.dim, size: 13)
                    : KelolaType.display(color: c.dim, size: 15)),
            isDense: true,
            filled: true,
            fillColor: c.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
              borderSide: BorderSide(color: c.amber),
            ),
          ),
        ),
      ],
    );
  }
}

/// AppBar kicker: machine facts in mono, optional READ-ONLY mode pill.
class KickerLine extends StatelessWidget {
  final String machine;
  final bool readOnly;
  final VoidCallback? onToggleReadOnly;

  const KickerLine({
    super.key,
    required this.machine,
    this.readOnly = false,
    this.onToggleReadOnly,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final machineStyle = KelolaType.mono(
      color: c.dim,
      size: 8.5,
      letterSpacing: 0.9,
    );
    return GestureDetector(
      onTap: onToggleReadOnly,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          if (machine.isNotEmpty)
            Flexible(
              child: Text(
                machine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: machineStyle,
              ),
            ),
          if (readOnly) ...[
            if (machine.isNotEmpty) Text(' · ', style: machineStyle),
            const ModePill(label: 'Read-only', active: true),
          ],
        ],
      ),
    );
  }
}

/// Error with a next step: title, body, copyable mono snippet.
class ActionableError extends StatelessWidget {
  final String title;
  final String body;
  final String snippet;

  const ActionableError({
    super.key,
    required this.title,
    required this.body,
    required this.snippet,
  });

  factory ActionableError.sudo({Key? key, String user = 'YOURUSER'}) {
    return ActionableError(
      key: key,
      title: sudoRequiredTitle,
      body: sudoRequiredBody,
      snippet: kelolaSudoersLine(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return RiskBand(
      risk: RiskLevel.read,
      status: HealthStatus.failed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KelolaType.display(color: c.text, size: 15)),
          const SizedBox(height: 6),
          Text(body, style: KelolaType.body(color: c.muted, size: 13)),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(KelolaRadii.sm),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    snippet,
                    style: KelolaType.mono(color: c.text, size: 11),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.copy, size: 16, color: c.muted),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: snippet));
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Red body copy, or [ActionableError] when the message is a sudo password gate.
class KelolaError extends StatelessWidget {
  final String message;
  final String? sudoUser;

  const KelolaError({super.key, required this.message, this.sudoUser});

  @override
  Widget build(BuildContext context) {
    if (looksLikeSudoRequired(message)) {
      return ActionableError.sudo(user: sudoUser ?? 'YOURUSER');
    }
    return Text(
      message,
      style: KelolaType.body(color: context.kc.red, size: 13),
    );
  }
}

Future<void> showSudoHintSheet(
  BuildContext context, {
  String user = 'YOURUSER',
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        child: ActionableError.sudo(user: user),
      );
    },
  );
}

/// Dashboard footer: when the snapshot was taken, plus read-only / sudo gates.
class DashboardStatusLine extends StatelessWidget {
  final DateTime? checkedAt;
  final DateTime? now;
  final bool readOnly;
  final bool sudoNeedsPassword;
  final String sudoUser;

  const DashboardStatusLine({
    super.key,
    this.checkedAt,
    this.now,
    this.readOnly = false,
    this.sudoNeedsPassword = false,
    this.sudoUser = 'YOURUSER',
  });

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final line = dashboardStatusLine(
      checkedAt: checkedAt,
      now: now,
      readOnly: readOnly,
      sudoNeedsPassword: sudoNeedsPassword,
    );
    if (line.isEmpty) {
      return const SizedBox.shrink();
    }
    final muted = KelolaType.body(color: c.muted, size: 12);
    final error = KelolaType.body(color: c.red, size: 12);
    final Widget text;
    if (sudoNeedsPassword) {
      final prefix = dashboardStatusLine(
        checkedAt: checkedAt,
        now: now,
        readOnly: readOnly,
      );
      text = Text.rich(
        TextSpan(
          children: [
            if (prefix.isNotEmpty) TextSpan(text: '$prefix · ', style: muted),
            TextSpan(text: sudoMutateWillFail, style: error),
          ],
        ),
      );
    } else {
      text = Text(line, style: muted);
    }
    if (!sudoNeedsPassword) {
      return text;
    }
    return GestureDetector(
      onTap: () => showSudoHintSheet(context, user: sudoUser),
      behavior: HitTestBehavior.opaque,
      child: text,
    );
  }
}

/// Section header matching the S08 unit-list slab.
class SectionSlab extends StatelessWidget {
  final String label;

  const SectionSlab(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 3),
      child: Text(
        label.toUpperCase(),
        style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
      ),
    );
  }
}

/// Distro mark from cached os-release ID. Paint uses the surrounding
/// chrome token, never a hardcoded brand color.
class OsIcon extends StatelessWidget {
  final OsIconKind kind;
  final double size;

  const OsIcon({super.key, required this.kind, this.size = 16});

  factory OsIcon.forOsId(String? osId, {Key? key, double size = 16}) {
    return OsIcon(key: key, kind: osIconKind(osId), size: size);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OsIconPainter(kind: kind, color: context.kc.muted),
      ),
    );
  }
}

class _OsIconPainter extends CustomPainter {
  _OsIconPainter({required this.kind, required this.color});

  final OsIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.08
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    switch (kind) {
      case OsIconKind.ubuntu:
        _ubuntu(canvas, size, paint, fill);
      case OsIconKind.debian:
        _debian(canvas, size, paint);
      case OsIconKind.fedora:
        _fedora(canvas, size, paint);
      case OsIconKind.alpine:
        _alpine(canvas, size, fill);
      case OsIconKind.arch:
        _arch(canvas, size, fill);
      case OsIconKind.rhel:
        _rhel(canvas, size, paint, fill);
      case OsIconKind.linux:
        _linux(canvas, size, paint, fill);
    }
  }

  void _ubuntu(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.28;
    canvas.drawCircle(c, r, stroke);
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 3;
      final dx = c.dx + (r + size.width * 0.16) * math.cos(a);
      final dy = c.dy + (r + size.width * 0.16) * math.sin(a);
      canvas.drawCircle(Offset(dx, dy), size.width * 0.09, fill);
    }
  }

  void _debian(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * 0.62, size.height * 0.18)
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.28,
        size.width * 0.86,
        size.height * 0.78,
        size.width * 0.48,
        size.height * 0.86,
      )
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.92,
        size.width * 0.12,
        size.height * 0.52,
        size.width * 0.38,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.55,
        size.height * 0.22,
        size.width * 0.58,
        size.height * 0.42,
        size.width * 0.48,
        size.height * 0.48,
      );
    canvas.drawPath(path, stroke);
  }

  void _fedora(Canvas canvas, Size size, Paint stroke) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.52),
        width: size.width * 0.78,
        height: size.height * 0.62,
      ),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 0.32),
      Offset(size.width * 0.38, size.height * 0.72),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 0.5),
      Offset(size.width * 0.68, size.height * 0.5),
      stroke,
    );
  }

  void _alpine(Canvas canvas, Size size, Paint fill) {
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.82)
      ..lineTo(size.width * 0.32, size.height * 0.38)
      ..lineTo(size.width * 0.48, size.height * 0.62)
      ..lineTo(size.width * 0.7, size.height * 0.22)
      ..lineTo(size.width * 0.92, size.height * 0.82)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _arch(Canvas canvas, Size size, Paint fill) {
    final path = Path()
      ..moveTo(size.width * 0.5, size.height * 0.08)
      ..lineTo(size.width * 0.88, size.height * 0.88)
      ..lineTo(size.width * 0.68, size.height * 0.88)
      ..lineTo(size.width * 0.5, size.height * 0.42)
      ..lineTo(size.width * 0.32, size.height * 0.88)
      ..lineTo(size.width * 0.12, size.height * 0.88)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _rhel(Canvas canvas, Size size, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.18,
          size.height * 0.28,
          size.width * 0.64,
          size.height * 0.42,
        ),
        Radius.circular(size.width * 0.18),
      ),
      fill,
    );
    canvas.drawLine(
      Offset(size.width * 0.1, size.height * 0.72),
      Offset(size.width * 0.9, size.height * 0.72),
      stroke,
    );
  }

  void _linux(Canvas canvas, Size size, Paint stroke, Paint fill) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.32),
        width: size.width * 0.42,
        height: size.height * 0.38,
      ),
      fill,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.68),
        width: size.width * 0.62,
        height: size.height * 0.5,
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _OsIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
