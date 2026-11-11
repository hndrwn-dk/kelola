import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';

/// Tile meta: `1.24.0 · running`, `stopped`, `installed`.
String stackTileMeta(DetectedService s) {
  final version = s.version?.trim() ?? '';
  return version.isEmpty ? s.state.name : '$version · ${s.state.name}';
}

/// M52 §3: the dashboard STACK section. One [ToolTile] per detected service
/// that has a lens, 3 per row. Hidden when there is nothing to show.
class StackSection extends StatelessWidget {
  const StackSection({
    super.key,
    required this.detection,
    required this.now,
    required this.onOpen,
  });

  /// Last detection read (cached or fresh). Null: never read.
  final ServiceDetection? detection;

  /// Clock for the age label; passed in so tests are deterministic.
  final DateTime now;
  final void Function(DetectedService) onOpen;

  /// The 15-minute rule ([Host.attentionFreshFor]).
  static bool isStale(ServiceDetection d, DateTime now) =>
      now.toUtc().difference(d.readAt.toUtc()) > Host.attentionFreshFor;

  @override
  Widget build(BuildContext context) {
    final d = detection;
    final shown = [
      if (d != null)
        for (final s in d.services)
          if (hasLens(s.id)) s,
    ];
    if (d == null || shown.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.kc;
    final label = KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9);
    final stale = isStale(d, now);
    final rows = <Widget>[];
    for (var i = 0; i < shown.length; i += 3) {
      final chunk = shown.skip(i).take(3).toList();
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 7));
      }
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 3; j++) ...[
              if (j > 0) const SizedBox(width: 7),
              Expanded(
                child: j < chunk.length
                    ? ToolTile(
                        label: descriptorFor(chunk[j].id).label,
                        meta: stackTileMeta(chunk[j]),
                        status: chunk[j].state == ServiceState.failed
                            ? HealthStatus.failed
                            : null,
                        onTap: () => onOpen(chunk[j]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            Text('STACK', style: label),
            const Spacer(),
            Text(
              'read ${Host.ageLabel(d.readAt, now: now)}',
              style: KelolaType.mono(
                color: stale ? c.forHealth(HealthStatus.warning) : c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...rows,
      ],
    );
  }
}
