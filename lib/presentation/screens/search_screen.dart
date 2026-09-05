import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/presentation/screens/container_detail_screen.dart';
import 'package:kelola/presentation/screens/host_dashboard_screen.dart';
import 'package:kelola/presentation/screens/unit_detail_screen.dart';
import 'package:kelola/presentation/widgets/kelola_chrome.dart' show KelolaEmpty;
import 'package:kelola/providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _q = '';
  SearchFilter _filter = SearchFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    final hosts = ref.watch(hostsProvider).valueOrNull ?? [];
    final index = SearchIndex(
      hosts: hosts,
      units: ref.watch(cachedSearchUnitsProvider),
      containers: ref.watch(cachedSearchContainersProvider),
    );
    final view = const InventorySearch().query(index, _q, filter: _filter);
    final kicker = searchKicker(idle: view.idle, counts: view.counts);

    return Scaffold(
      backgroundColor: c.ink,
      appBar: AppBar(
        backgroundColor: c.ink,
        foregroundColor: c.text,
        elevation: 0,
        title: Column(
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
                    hintText: 'Hosts, units, containers',
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
                const SizedBox(height: 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final filter in SearchFilter.values)
                      FilterPill(
                        label: searchChipLabel(filter, view.counts),
                        selected: _filter == filter,
                        onTap: () => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: view.hits.isEmpty
                ? Center(
                    child: KelolaEmpty(
                      body: searchEmptyCopy(_filter, idle: view.idle),
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
    if (host != null) {
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
    final unit = hit.unit?.unit;
    if (unit != null) {
      if (hit.isIndexStale()) {
        return HealthStatus.unknown;
      }
      if (unit.isFailed) {
        return HealthStatus.failed;
      }
      if (unit.isActive) {
        return HealthStatus.healthy;
      }
      return HealthStatus.unknown;
    }
    final row = hit.container?.row;
    if (row != null) {
      if (hit.isIndexStale()) {
        return HealthStatus.unknown;
      }
      return switch (containerHealth(row)) {
        ContainerHealth.healthy => HealthStatus.healthy,
        ContainerHealth.warning => HealthStatus.warning,
        ContainerHealth.failed => HealthStatus.failed,
        ContainerHealth.unknown => HealthStatus.unknown,
      };
    }
    return HealthStatus.unknown;
  }

  Future<void> _open(SearchHit hit, List<Host> hosts) async {
    final host = _hostOf(hit, hosts);
    if (host == null) {
      return;
    }
    if (hit.kind == SearchKind.host) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HostDashboardScreen(hostId: host.id),
        ),
      );
      return;
    }
    final facts = await ref.read(hostRepositoryProvider).facts(host.id) ??
        HostFacts.undiscovered;
    if (!mounted) {
      return;
    }
    if (hit.kind == SearchKind.unit) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UnitDetailScreen(
            host: host,
            facts: facts,
            unitName: hit.name,
          ),
        ),
      );
      return;
    }
    final row = hit.container?.row;
    if (row == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContainerDetailScreen(
          host: host,
          facts: facts,
          row: row,
        ),
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
