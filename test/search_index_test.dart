import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
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

  test('unit and container list probes do not enter host search', () async {
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

    expect(await repo.listSearchUnits(), isEmpty);
    expect(await repo.listSearchContainers(), isEmpty);
    final view = const InventorySearch().query(
      SearchIndex(hosts: [host]),
      'nginx',
    );
    expect(view.hits, isEmpty);
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
      parsed: const DashboardSnapshot(
        uptime: Duration(hours: 1),
        load1: 0.1,
        cpuPercent: 1,
        memUsedPercent: 10,
        diskRootPercent: 20,
        failedUnitCount: 1,
        failedUnitNames: ['nginx.service'],
      ),
    );
    expect(await repo.listFailedUnitNames(host.id), ['nginx.service']);
    await repo.delete(host.id);
    expect(await repo.listFailedUnitNames(host.id), isEmpty);
  });

  test('session pool writes the index after a successful parse', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, contains('writeSearchIndexFromProbe'));
    expect(src, contains('parsed: parsed'));
  });
}
