import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
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
    final view = const InventorySearch().query(SearchIndex(hosts: hosts), _q);
    final kicker = searchKicker(idle: view.idle, counts: view.counts);

    return KelolaWashScaffold(
      appBar: AppBar(
        backgroundColor: c.ink.withValues(alpha: 0),
        surfaceTintColor: c.ink.withValues(alpha: 0),
        forceMaterialTransparency: true,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              kicker,
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  autofocus: true,
                  style: KelolaType.display(color: c.text, size: 16),
                  cursorColor: c.amber,
                  decoration: InputDecoration(
                    hintText: 'Host name, address, or tag',
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
              ],
            ),
          ),
          Expanded(
            child: view.hits.isEmpty
                ? Center(
                    child: KelolaEmpty(
                      body: searchEmptyCopy(idle: view.idle),
                    ),
                  )
                : ListView.builder(
                    padding: kelolaScrollPadding(context),
                    itemCount: view.hits.length,
                    itemBuilder: (context, i) {
                      final hit = view.hits[i];
                      final health = _health(hit);
                      final host = hit.host;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ServiceRow(
                          risk: RiskLevel.read,
                          status: health,
                          name: hit.name,
                          meta: hit.meta,
                          pillText: host?.attentionPill(),
                          pillStatus: host == null ? null : health,
                          onTap: () => _open(hit, hosts),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  HealthStatus _health(SearchHit hit) {
    final host = hit.host;
    if (host == null || host.attentionAt == null || host.isAttentionStale()) {
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

  Future<void> _open(SearchHit hit, List<Host> hosts) async {
    final host = _hostOf(hit, hosts);
    if (host == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HostDashboardScreen(hostId: host.id),
      ),
    );
  }

  Host? _hostOf(SearchHit hit, List<Host> hosts) {
    if (hit.host != null) {
      return hit.host;
    }
    for (final host in hosts) {
      if (host.id == hit.hostId || host.alias == hit.hostId) {
        return host;
      }
    }
    final alias = hit.unit?.hostAlias ?? hit.container?.hostAlias;
    if (alias == null) {
      return null;
    }
    for (final host in hosts) {
      if (host.alias == alias) {
        return host;
      }
    }
    return null;
  }
}
