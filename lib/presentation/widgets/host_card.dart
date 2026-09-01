import 'package:flutter/material.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/presentation/theme/kelola_theme.dart';
import 'package:kelola/presentation/widgets/risk_band.dart';

class HostCard extends StatelessWidget {
  const HostCard({super.key, required this.host, required this.onTap});

  final Host host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<KelolaColors>()!;
    final level = switch (host.attention) {
      HostAttention.failedUnits => RiskLevel.destructive,
      HostAttention.diskHigh => RiskLevel.mutate,
      HostAttention.unreachable => RiskLevel.read,
      HostAttention.healthy => RiskLevel.read,
      HostAttention.unknown => RiskLevel.read,
    };
    final pill = switch (host.attention) {
      HostAttention.failedUnits => ('failed', colors.red),
      HostAttention.diskHigh => ('disk', colors.amber),
      HostAttention.unreachable => ('offline', colors.dim),
      HostAttention.healthy => ('healthy', colors.green),
      HostAttention.unknown => ('new', colors.muted),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: RiskBand(
          level: level,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.alias,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      host.subtitle,
                      style: TextStyle(color: colors.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                pill.$1,
                style: TextStyle(color: pill.$2, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
