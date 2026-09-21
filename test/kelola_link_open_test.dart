import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/deep_link.dart';
import 'package:kelola/presentation/kelola_link_open.dart';

void main() {
  test('missing host returns null; flags map onto the dashboard', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );

    expect(
      await dashboardForLink(repo, const KelolaLink(hostId: 'missing')),
      isNull,
    );
    expect(await dashboardForLink(repo, const KelolaLink()), isNull);

    final dash = await dashboardForLink(
      repo,
      KelolaLink(hostId: host.id, incident: true),
    );
    expect(dash, isNotNull);
    expect(dash!.hostId, host.id);
    expect(dash.openIncident, isTrue);
    expect(dash.openTunnels, isFalse);
    expect(dash.openUnitName, isNull);

    final tunnels = await dashboardForLink(
      repo,
      KelolaLink(hostId: host.id, tunnel: true),
    );
    expect(tunnels!.openTunnels, isTrue);

    final unit = await dashboardForLink(
      repo,
      KelolaLink(hostId: host.id, unitName: 'nginx.service'),
    );
    expect(unit!.openUnitName, 'nginx.service');
  });
}
