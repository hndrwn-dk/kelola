import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart';
import 'package:kelola/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hosts = ref.watch(hostsProvider).valueOrNull ?? [];
    final hits = const InventorySearch().query(hosts, _q);

    return KelolaPage(
      title: 'Find',
      kicker: _q.trim().isEmpty ? 'ON THIS PHONE' : '${hits.length} MATCHES',
      top: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: TextField(
          autofocus: true,
          style: KelolaType.display(color: c.text, size: 16),
          cursorColor: c.amber,
          decoration: InputDecoration(
            hintText: 'Hosts, addresses, notes',
            hintStyle: KelolaType.display(color: c.dim, size: 16),
            filled: false,
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: hits.isEmpty
          ? Center(
              child: KelolaEmpty(
                body: _q.trim().isEmpty
                    ? 'Search aliases, addresses, users, and notes on this phone.'
                    : 'No hosts match.',
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
              itemCount: hits.length,
              itemBuilder: (context, i) {
                final host = hits[i];
                final health = _health(host);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ServiceRow(
                    risk: RiskLevel.read,
                    status: health,
                    name: host.alias,
                    meta: host.subtitle,
                    pillText: host.attentionPill(),
                    pillStatus: health,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => HostDashboardScreen(hostId: host.id),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  HealthStatus _health(Host host) {
    if (host.attentionAt == null || host.isAttentionStale()) {
      return HealthStatus.unknown;
    }
    return switch (host.attention) {
      HostAttention.failedUnits => HealthStatus.failed,
      HostAttention.diskHigh => HealthStatus.warning,
      HostAttention.unreachable => HealthStatus.unknown,
      HostAttention.healthy => HealthStatus.healthy,
      HostAttention.unknown => HealthStatus.unknown,
    };
  }
}
