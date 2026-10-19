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
  List<String> tags = const [],
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
    tags: tags,
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
  test('search matches alias, address, and notes, not the login name', () {
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
    expect(
      const InventorySearch().query(index(hosts: hosts), 'hendra').hits,
      isEmpty,
    );
  });

  test('one tag finds every host that carries it', () {
    final hosts = [
      host('web-01', address: '10.0.0.8', tags: const ['prod', 'edge']),
      host('web-02', address: '10.0.0.9', tags: const ['prod']),
      host('nas-01', address: '10.0.0.10', tags: const ['lab']),
    ];
    final hits = const InventorySearch().query(index(hosts: hosts), 'Prod').hits;
    expect(hits.map((h) => h.name), ['web-01', 'web-02']);
    expect(hits.map((h) => h.meta), [
      'host · 10.0.0.8 · prod',
      'host · 10.0.0.9 · prod',
    ]);
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
      searchEmptyCopy(idle: true),
      'Search hosts by name, address, or tag.',
    );
    expect(
      searchEmptyCopy(idle: false),
      'No hosts match.',
    );
    expect(
      searchEmptyCopy(idle: true),
      isNot(searchEmptyCopy(idle: false)),
    );
  });

  test('unit and container names are not inventory matches', () {
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
    final view = const InventorySearch().query(snap, 'nginx');
    expect(view.hits.map((h) => h.name), ['nginx-edge']);
    expect(view.hits.map((h) => h.kind), [SearchKind.host]);
    expect(view.counts.hosts, 1);
    expect(view.counts.all, 1);
    expect(view.hits.single.meta, 'host · 10.0.0.9');
  });

  test('query is a pure function: no repository or session is required', () {
    final view = const InventorySearch().query(
      index(hosts: [host('nas-01', address: '192.168.1.24')]),
      '192.168.1',
    );
    expect(view.hits.single.kind, SearchKind.host);
    expect(view.hits.single.name, 'nas-01');
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
