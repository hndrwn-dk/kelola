import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/search/inventory_search.dart';
import 'package:kelola/domain/search/search_index_write.dart';
import 'package:kelola/domain/units/service_unit.dart';

ServiceUnit _unit(String name) {
  return ServiceUnit(
    name: name,
    description: '',
    load: 'loaded',
    active: 'active',
    sub: 'running',
  );
}

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() async {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('UnitsProbe success indexes nginx on host A; query does not SSH',
      () async {
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '192.168.18.114',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service'), _unit('sshd.service')],
        initSupported: true,
      ),
    );

    final units = await repo.listSearchUnits();
    final index = SearchIndex(units: units);
    final view = const InventorySearch().query(index, 'nginx');

    expect(view.hits, hasLength(1));
    expect(view.hits.single.kind, SearchKind.unit);
    expect(view.hits.single.name, 'nginx.service');
    expect(view.hits.single.origin, 'east-worker-uat');
    expect(view.hits.single.hostId, host.id);
    expect(view.counts.units, 1);
  });

  test('ContainerListProbe success indexes nginx on host A', () async {
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '192.168.18.114',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: const ContainerInventory(
        rows: [
          ContainerRow(
            id: 'c1',
            names: 'nginx',
            image: 'nginx:latest',
            state: 'running',
            status: 'Up 2 days',
          ),
        ],
      ),
    );

    final containers = await repo.listSearchContainers();
    final view = const InventorySearch().query(
      SearchIndex(containers: containers),
      'nginx',
    );

    expect(view.hits, hasLength(1));
    expect(view.hits.single.kind, SearchKind.container);
    expect(view.hits.single.name, 'nginx');
    expect(view.hits.single.origin, 'east-worker-uat');
    expect(view.hits.single.hostId, host.id);
  });

  test('replace drops units that disappeared on the host', () async {
    final host = await repo.insert(
      alias: 'web-prod',
      address: '10.0.4.11',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service'), _unit('ghost.service')],
        initSupported: true,
      ),
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service')],
        initSupported: true,
      ),
    );

    final names = (await repo.listSearchUnits()).map((u) => u.unit.name);
    expect(names, ['nginx.service']);
    expect(names, isNot(contains('ghost.service')));
  });

  test('stale index older than 15 minutes is marked with age', () async {
    final now = DateTime.utc(2026, 9, 3, 8);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '192.168.18.114',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service')],
        initSupported: true,
      ),
      now: now.subtract(const Duration(minutes: 20)),
    );

    final units = await repo.listSearchUnits();
    expect(units.single.isIndexStale(now: now), isTrue);

    final view = const InventorySearch().query(
      SearchIndex(units: units),
      'nginx',
      now: now,
    );
    expect(view.hits, hasLength(1));
    expect(view.hits.single.meta, 'unit · east-worker-uat · 20m ago');
    expect(view.hits.single.isIndexStale(now: now), isTrue);
  });

  test('fresh index under 15 minutes is not marked stale', () async {
    final now = DateTime.utc(2026, 9, 3, 8);
    final host = await repo.insert(
      alias: 'east-worker-uat',
      address: '192.168.18.114',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service')],
        initSupported: true,
      ),
      now: now.subtract(const Duration(minutes: 4)),
    );

    final units = await repo.listSearchUnits();
    expect(units.single.isIndexStale(now: now), isFalse);

    final view = const InventorySearch().query(
      SearchIndex(units: units),
      'nginx',
      now: now,
    );
    expect(view.hits.single.meta, 'unit · east-worker-uat');
  });

  test('deleting a host drops its search index rows', () async {
    final host = await repo.insert(
      alias: 'gone',
      address: '10.0.0.9',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: UnitListResult(
        units: [_unit('nginx.service')],
        initSupported: true,
      ),
    );
    await repo.delete(host.id);
    expect(await repo.listSearchUnits(), isEmpty);
  });

  test('session pool writes the index after a successful parse', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('writeSearchIndexFromProbe'));
    expect(src, contains('parsed: parsed'));
  });
}
