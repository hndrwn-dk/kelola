import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';

/// Tile meta: `1.24.0 · running`, `stopped`, `installed`; a container
/// service (M52c) names its container: `lamp-web · running`.
String stackTileMeta(DetectedService s) {
  final container = s.container;
  if (container != null) {
    return '$container · ${s.state.name}';
  }
  final version = s.version?.trim() ?? '';
  return version.isEmpty ? s.state.name : '$version · ${s.state.name}';
}

/// M52c: a container service that gets no tile of its own: stopped (exited,
/// created, paused, dead). Running and failed (restarting) containers keep
/// theirs; host services always do.
bool isCollapsedStackService(DetectedService s) =>
    s.inContainer && s.state == ServiceState.stopped;

/// Meta of the one tile that stands for the stopped containers.
String stoppedContainersMeta(int n) => n == 1 ? '1 container' : '$n containers';

/// M52 §3: the dashboard STACK section. One [ToolTile] per detected service
/// that has a lens, 3 per row. Stopped container services (M52c) share one
/// "Stopped" tile that opens Containers. Hidden when there is nothing to show.
class StackSection extends StatelessWidget {
  const StackSection({
    super.key,
    required this.detection,
    required this.now,
    required this.onOpen,
    required this.onOpenContainers,
  });

  /// Last detection read (cached or fresh). Null: never read.
  final ServiceDetection? detection;

  /// Clock for the age label; passed in so tests are deterministic.
  final DateTime now;
  final void Function(DetectedService) onOpen;

  /// The "Stopped" tile: opens the Containers screen.
  final VoidCallback onOpenContainers;

  /// The 15-minute rule ([Host.attentionFreshFor]).
  static bool isStale(ServiceDetection d, DateTime now) =>
      now.toUtc().difference(d.readAt.toUtc()) > Host.attentionFreshFor;

  @override
  Widget build(BuildContext context) {
    final d = detection;
    final withLens = [
      if (d != null)
        for (final s in d.services)
          if (hasLens(s.id)) s,
    ];
    final stopped = withLens.where(isCollapsedStackService).length;
    final tiles = <Widget>[
      for (final s in withLens)
        if (!isCollapsedStackService(s))
          ToolTile(
            label: descriptorFor(s.id).label,
            meta: stackTileMeta(s),
            status: s.state == ServiceState.failed ? HealthStatus.failed : null,
            onTap: () => onOpen(s),
          ),
      if (stopped > 0)
        ToolTile(
          label: 'Stopped',
          meta: stoppedContainersMeta(stopped),
          onTap: onOpenContainers,
        ),
    ];
    if (d == null || tiles.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.kc;
    final label = KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9);
    final stale = isStale(d, now);
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 3) {
      final chunk = tiles.skip(i).take(3).toList();
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 7));
      }
      rows.add(
        Row(
          children: [
            for (var j = 0; j < 3; j++) ...[
              if (j > 0) const SizedBox(width: 7),
              Expanded(
                child: j < chunk.length ? chunk[j] : const SizedBox.shrink(),
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
