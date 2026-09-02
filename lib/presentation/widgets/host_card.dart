import 'package:flutter/material.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/presentation/theme/kelola_fonts.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/ops_dash.dart';

class HostFeatured extends StatelessWidget {
  const HostFeatured({
    super.key,
    required this.host,
    required this.onTap,
    this.onDelete,
    this.live = false,
  });

  final Host host;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return HostCard(
      host: host,
      onTap: onTap,
      onDelete: onDelete,
      live: live,
    );
  }
}

class HostIndexRow extends StatelessWidget {
  const HostIndexRow({
    super.key,
    required this.host,
    required this.onTap,
    this.onDelete,
    this.live = false,
  });

  final Host host;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return HostCard(
      host: host,
      onTap: onTap,
      onDelete: onDelete,
      live: live,
    );
  }
}

class HostCard extends StatelessWidget {
  const HostCard({
    super.key,
    required this.host,
    required this.onTap,
    this.onDelete,
    this.live = false,
  });

  final Host host;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final status = _status(host, colors);
    final card = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DashCard(
        accent: status.$2,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.$1,
                    style: KelolaFonts.machine(
                      color: status.$2,
                      size: 10,
                      weight: FontWeight.w500,
                    ).copyWith(letterSpacing: 0.12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    host.alias,
                    style: KelolaFonts.title(size: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    live
                        ? (host.lastRttMs == null
                            ? '${host.subtitle} · session'
                            : '${host.subtitle} · ${host.lastRttMs}ms')
                        : host.subtitle,
                    style: KelolaFonts.machine(color: colors.dim, size: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Remove host',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Text(
                  '×',
                  style: TextStyle(
                    color: colors.dim,
                    fontSize: 20,
                    height: 1,
                  ),
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );

    if (onDelete == null) {
      return card;
    }
    return Dismissible(
      key: ValueKey(host.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: colors.red.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'REMOVE',
          style: KelolaFonts.machine(
            color: colors.red,
            size: 11,
            weight: FontWeight.w500,
          ),
        ),
      ),
      confirmDismiss: (_) async {
        await onDelete!();
        return false;
      },
      child: card,
    );
  }
}

(String, Color) _status(Host host, KelolaColors colors) {
  return switch (host.attention) {
    HostAttention.failedUnits => ('FAILED', colors.red),
    HostAttention.diskHigh => ('DISK', colors.amber),
    HostAttention.unreachable => ('OFFLINE', colors.dim),
    HostAttention.healthy =>
      host.readOnly ? ('READ-ONLY', colors.muted) : ('HEALTHY', colors.green),
    HostAttention.unknown => ('NEW', colors.muted),
  };
}
