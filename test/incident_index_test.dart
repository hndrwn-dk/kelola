import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/search/search_index_write.dart';

void main() {
  test('dashboard probe success indexes failed unit names for the incident sheet',
      () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.8',
      port: 22,
      username: 'hendra',
    );
    await writeSearchIndexFromProbe(
      repo: repo,
      hostId: host.id,
      parsed: const DashboardSnapshot(
        uptime: Duration(hours: 3),
        load1: 0.2,
        cpuPercent: 4,
        memUsedPercent: 30,
        diskRootPercent: 40,
        failedUnitCount: 2,
        failedUnitNames: ['nginx.service', 'borgmatic.service'],
      ),
    );
    expect(
      await repo.listFailedUnitNames(host.id),
      unorderedEquals(['nginx.service', 'borgmatic.service']),
    );
  });

  test('hosts list chip and dashboard open incident; pool ingests cache', () {
    expect(
      File('lib/presentation/screens/hosts_screen.dart').readAsStringSync(),
      contains('onPillTap'),
    );
    expect(
      File('lib/presentation/screens/host_dashboard_screen.dart')
          .readAsStringSync(),
      contains('openHostIncident'),
    );
    expect(
      File('lib/data/ssh/session_pool.dart').readAsStringSync(),
      contains('_correlation.ingest'),
    );
  });
}
