import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/units/service_unit.dart';

enum SearchKind { host, unit, container }

enum SearchFilter { hosts, units, containers, all }

class SearchUnit {
  const SearchUnit({
    required this.hostId,
    required this.hostAlias,
    required this.unit,
    this.indexedAt,
  });

  final String hostId;
  final String hostAlias;
  final ServiceUnit unit;
  final DateTime? indexedAt;

  bool isIndexStale({DateTime? now}) => isSearchIndexStale(indexedAt, now: now);
}

class SearchContainer {
  const SearchContainer({
    required this.hostId,
    required this.hostAlias,
    required this.row,
    this.indexedAt,
  });

  final String hostId;
  final String hostAlias;
  final ContainerRow row;
  final DateTime? indexedAt;

  bool isIndexStale({DateTime? now}) => isSearchIndexStale(indexedAt, now: now);
}

/// Same 15-minute window as [Host.attentionFreshFor].
bool isSearchIndexStale(DateTime? indexedAt, {DateTime? now}) {
  final at = indexedAt;
  if (at == null) {
    return false;
  }
  final n = (now ?? DateTime.now()).toUtc();
  return n.difference(at.toUtc()) > Host.attentionFreshFor;
}

class SearchIndex {
  const SearchIndex({
    this.hosts = const [],
    this.units = const [],
    this.containers = const [],
  });

  final List<Host> hosts;
  final List<SearchUnit> units;
  final List<SearchContainer> containers;
}

class SearchCounts {
  const SearchCounts({
    required this.hosts,
    required this.units,
    required this.containers,
  });

  static const empty = SearchCounts(hosts: 0, units: 0, containers: 0);

  final int hosts;
  final int units;
  final int containers;

  int get all => hosts + units + containers;
}

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.name,
    required this.origin,
    required this.hostId,
    this.host,
    this.unit,
    this.container,
    this.indexedAt,
    this.now,
  });

  final SearchKind kind;
  final String name;
  final String origin;
  final String hostId;
  final Host? host;
  final SearchUnit? unit;
  final SearchContainer? container;
  final DateTime? indexedAt;
  final DateTime? now;

  bool isIndexStale({DateTime? now}) =>
      isSearchIndexStale(indexedAt, now: now ?? this.now);

  String get meta {
    final base = '${_kindLabel(kind)} · $origin';
    if (kind == SearchKind.host || !isIndexStale()) {
      return base;
    }
    return '$base · ${Host.ageLabel(indexedAt!, now: now)}';
  }
}

class SearchView {
  const SearchView({
    required this.hits,
    required this.counts,
    required this.idle,
  });

  final List<SearchHit> hits;
  final SearchCounts counts;
  final bool idle;
}

class InventorySearch {
  const InventorySearch();

  SearchView query(
    SearchIndex index,
    String raw, {
    SearchFilter filter = SearchFilter.all,
    DateTime? now,
  }) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) {
      return const SearchView(
        hits: [],
        counts: SearchCounts.empty,
        idle: true,
      );
    }

    final hosts = <SearchHit>[];
    for (final h in index.hosts) {
      if (_hostMatches(h, q)) {
        hosts.add(
          SearchHit(
            kind: SearchKind.host,
            name: h.alias,
            origin: h.address,
            hostId: h.id,
            host: h,
          ),
        );
      }
    }

    final units = <SearchHit>[];
    for (final u in index.units) {
      if (_unitMatches(u, q)) {
        units.add(
          SearchHit(
            kind: SearchKind.unit,
            name: u.unit.name,
            origin: u.hostAlias,
            hostId: u.hostId,
            unit: u,
            indexedAt: u.indexedAt,
            now: now,
          ),
        );
      }
    }

    final containers = <SearchHit>[];
    for (final c in index.containers) {
      if (_containerMatches(c, q)) {
        containers.add(
          SearchHit(
            kind: SearchKind.container,
            name: c.row.title,
            origin: c.hostAlias,
            hostId: c.hostId,
            container: c,
            indexedAt: c.indexedAt,
            now: now,
          ),
        );
      }
    }

    final counts = SearchCounts(
      hosts: hosts.length,
      units: units.length,
      containers: containers.length,
    );
    final hits = switch (filter) {
      SearchFilter.hosts => hosts,
      SearchFilter.units => units,
      SearchFilter.containers => containers,
      SearchFilter.all => [...hosts, ...units, ...containers],
    };
    return SearchView(hits: hits, counts: counts, idle: false);
  }
}

bool _hostMatches(Host host, String q) {
  return host.alias.toLowerCase().contains(q) ||
      host.address.toLowerCase().contains(q) ||
      (host.note?.toLowerCase().contains(q) ?? false) ||
      host.username.toLowerCase().contains(q);
}

bool _unitMatches(SearchUnit item, String q) {
  return item.unit.name.toLowerCase().contains(q) ||
      item.unit.description.toLowerCase().contains(q);
}

bool _containerMatches(SearchContainer item, String q) {
  return item.row.names.toLowerCase().contains(q) ||
      item.row.image.toLowerCase().contains(q) ||
      item.row.title.toLowerCase().contains(q);
}

String _kindLabel(SearchKind kind) => switch (kind) {
      SearchKind.host => 'host',
      SearchKind.unit => 'unit',
      SearchKind.container => 'container',
    };

String searchChipLabel(SearchFilter filter, SearchCounts counts) {
  return switch (filter) {
    SearchFilter.hosts => 'Hosts ${counts.hosts}',
    SearchFilter.units => 'Units ${counts.units}',
    SearchFilter.containers => 'Containers ${counts.containers}',
    SearchFilter.all => 'All ${counts.all}',
  };
}

String searchEmptyCopy(SearchFilter filter, {required bool idle}) {
  if (idle) {
    return 'Search hosts, units, and containers already on this phone.';
  }
  return switch (filter) {
    SearchFilter.all => 'No matches.',
    SearchFilter.hosts => 'No hosts match.',
    SearchFilter.units => 'No units match.',
    SearchFilter.containers => 'No containers match.',
  };
}

String searchKicker({required bool idle, required SearchCounts counts}) {
  if (idle) {
    return 'LOCAL';
  }
  return '${counts.all} MATCHES';
}

int attentionRank(Host host) {
  switch (host.attention) {
    case HostAttention.failedUnits:
      return 0;
    case HostAttention.diskHigh:
      return 1;
    case HostAttention.unreachable:
      return 2;
    case HostAttention.unknown:
      return 3;
    case HostAttention.healthy:
      return 4;
  }
}

List<Host> sortByAttention(List<Host> hosts) {
  final copy = [...hosts];
  copy.sort((a, b) {
    final r = attentionRank(a).compareTo(attentionRank(b));
    if (r != 0) {
      return r;
    }
    return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
  });
  return copy;
}
