import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/domain/units/service_unit.dart';

Host host(
  String alias, {
  String address = '10.0.0.1',
  String? note,
  HostAttention attention = HostAttention.healthy,
}) {
  return Host(
    id: alias,
    alias: alias,
    address: address,
    port: 22,
    username: 'hendra',
    keyAlias: 'kelola-user',
    note: note,
    attention: attention,
  );
}

SearchUnit unitHit({
  required String hostAlias,
  required String name,
  String active = 'active',
  String sub = 'running',
}) {
  return SearchUnit(
    hostId: hostAlias,
    hostAlias: hostAlias,
    unit: ServiceUnit(
      name: name,
      description: '',
      load: 'loaded',
      active: active,
      sub: sub,
    ),
  );
}

SearchContainer containerHit({
  required String hostAlias,
  required String name,
}) {
  return SearchContainer(
    hostId: hostAlias,
    hostAlias: hostAlias,
    row: ContainerRow(
      id: name,
      names: name,
      image: 'img',
      state: 'running',
      status: 'Up 1 day',
    ),
  );
}

SearchIndex index({
  List<Host> hosts = const [],
  List<SearchUnit> units = const [],
  List<SearchContainer> containers = const [],
}) {
  return SearchIndex(hosts: hosts, units: units, containers: containers);
}

void main() {
  test('search matches alias, address, and notes locally', () {
    final hosts = [
      host('nas-01', address: '192.168.1.24', note: 'living-room NAS'),
      host('web-prod', address: '10.0.4.11'),
    ];
    expect(
      const InventorySearch().query(index(hosts: hosts), 'nas').hits.single.name,
      'nas-01',
    );
    expect(
      const InventorySearch()
          .query(index(hosts: hosts), '10.0.4')
          .hits
          .single
          .name,
      'web-prod',
    );
    expect(
      const InventorySearch()
          .query(index(hosts: hosts), 'living-room')
          .hits
          .single
          .name,
      'nas-01',
    );
  });

  test('blank query is idle: no hits, not a dump of inventory', () {
    final view = const InventorySearch().query(
      index(hosts: [host('nas-01')]),
      '  ',
    );
    expect(view.idle, isTrue);
    expect(view.hits, isEmpty);
    expect(view.counts.all, 0);
  });

  test('typed miss is not idle and has zero hits', () {
    final view = const InventorySearch().query(
      index(hosts: [host('nas-01')]),
      'zzz',
    );
    expect(view.idle, isFalse);
    expect(view.hits, isEmpty);
    expect(view.counts.all, 0);
  });

  test('idle and miss empty copy are distinct', () {
    expect(
      searchEmptyCopy(SearchFilter.all, idle: true),
      'Search hosts, units, and containers already on this phone.',
    );
    expect(
      searchEmptyCopy(SearchFilter.all, idle: false),
      'No matches.',
    );
    expect(
      searchEmptyCopy(SearchFilter.all, idle: true),
      isNot(searchEmptyCopy(SearchFilter.all, idle: false)),
    );
  });

  test('chips are pure filters with match counts, not a sort', () {
    final snap = index(
      hosts: [
        host('east-worker-uat', address: '192.168.18.114'),
        host('nginx-edge', address: '10.0.0.9'),
      ],
      units: [
        unitHit(hostAlias: 'east-worker-uat', name: 'nginx.service'),
      ],
      containers: [
        containerHit(hostAlias: 'east-worker-uat', name: 'nginx'),
      ],
    );
    const search = InventorySearch();
    final all = search.query(snap, 'nginx');
    expect(all.counts.hosts, 1);
    expect(all.counts.units, 1);
    expect(all.counts.containers, 1);
    expect(all.counts.all, 3);
    expect(all.hits.map((h) => h.kind).toList(), [
      SearchKind.host,
      SearchKind.unit,
      SearchKind.container,
    ]);
    expect(
      searchChipLabel(SearchFilter.hosts, all.counts),
      'Hosts 1',
    );
    expect(
      searchChipLabel(SearchFilter.units, all.counts),
      'Units 1',
    );
    expect(
      searchChipLabel(SearchFilter.containers, all.counts),
      'Containers 1',
    );
    expect(searchChipLabel(SearchFilter.all, all.counts), 'All 3');

    final hostsOnly = search.query(snap, 'nginx', filter: SearchFilter.hosts);
    expect(hostsOnly.hits.map((h) => h.kind), [SearchKind.host]);
    expect(hostsOnly.counts.all, 3);

    final unitsOnly = search.query(snap, 'nginx', filter: SearchFilter.units);
    expect(unitsOnly.hits.map((h) => h.kind), [SearchKind.unit]);

    final none = search.query(snap, 'nginx-edge', filter: SearchFilter.units);
    expect(none.hits, isEmpty);
    expect(none.counts.hosts, 1);
    expect(none.counts.units, 0);
    expect(
      searchEmptyCopy(SearchFilter.units, idle: false),
      'No units match.',
    );
  });

  test('meta sub-line is type · origin so cross-host hits are obvious', () {
    final snap = index(
      hosts: [host('east-worker-uat', address: '192.168.18.114')],
      units: [
        unitHit(hostAlias: 'east-worker-uat', name: 'nginx.service'),
      ],
      containers: [
        containerHit(hostAlias: 'east-worker-uat', name: 'nginx'),
      ],
    );
    final hits = const InventorySearch().query(snap, 'east').hits;
    expect(
      hits.firstWhere((h) => h.kind == SearchKind.host).meta,
      'host · 192.168.18.114',
    );

    final named = const InventorySearch().query(snap, 'nginx');
    expect(
      named.hits.firstWhere((h) => h.kind == SearchKind.unit).meta,
      'unit · east-worker-uat',
    );
    expect(
      named.hits.firstWhere((h) => h.kind == SearchKind.container).meta,
      'container · east-worker-uat',
    );
  });

  test('query is a pure function: no repository or session is required', () {
    final view = const InventorySearch().query(
      index(
        hosts: [host('nas-01', address: '192.168.1.24')],
        units: [unitHit(hostAlias: 'nas-01', name: 'sshd.service')],
      ),
      'sshd',
    );
    expect(view.hits.single.kind, SearchKind.unit);
    expect(view.hits.single.name, 'sshd.service');
  });

  test('attention sort puts failed units first', () {
    final hosts = [
      host('ok'),
      host('web-prod', attention: HostAttention.diskHigh),
      host('nas-01', attention: HostAttention.failedUnits),
    ];
    final sorted = sortByAttention(hosts);
    expect(sorted.first.alias, 'nas-01');
    expect(sorted[1].alias, 'web-prod');
  });
}
