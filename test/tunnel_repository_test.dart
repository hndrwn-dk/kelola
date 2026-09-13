import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/db/tunnel_repository.dart';
import 'package:kelola/domain/audit/audit_event.dart';
import 'package:kelola/domain/tunnels/tunnel_target.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository hosts;
  late TunnelRepository tunnels;

  setUp(() {
    db = KelolaDatabase.memory();
    hosts = HostRepository(db);
    tunnels = TunnelRepository(db);
  });

  tearDown(() => db.close());

  Future<String> insertHost() async {
    final host = await hosts.insert(
      alias: 'web-01',
      address: '10.0.0.1',
      port: 22,
      username: 'deploy',
    );
    return host.id;
  }

  test('upsert stores scheme as text; host delete cascades targets', () async {
    final hostId = await insertHost();
    await tunnels.upsert(
      TunnelTarget(
        id: 't1',
        hostId: hostId,
        label: 'Cockpit',
        remoteHost: '127.0.0.1',
        remotePort: 9090,
        scheme: TunnelScheme.https,
        path: '/',
      ),
    );

    final row = await (db.select(db.tunnelTargets)
          ..where((t) => t.id.equals('t1')))
        .getSingle();
    expect(row.scheme, 'https');
    expect(row.scheme, isA<String>());

    await hosts.delete(hostId);

    final remaining = await db.select(db.tunnelTargets).get();
    expect(remaining, isEmpty);
  });

  test('idleMinutes clamps on read and write', () async {
    expect(await tunnels.idleMinutes(), 10);

    await db.customStatement(
      'INSERT INTO app_settings (id, tunnel_idle_minutes) VALUES (1, 0) '
      'ON CONFLICT(id) DO UPDATE SET tunnel_idle_minutes = 0',
    );
    expect(await tunnels.idleMinutes(), 2);

    await tunnels.setIdleMinutes(99);
    expect(await tunnels.idleMinutes(), 60);

    final stored = await (db.select(db.appSettings)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    expect(stored.tunnelIdleMinutes, 60);
  });

  test('watchForHost orders by label then remotePort', () async {
    final hostId = await insertHost();
    await tunnels.upsert(
      TunnelTarget(
        id: 'b',
        hostId: hostId,
        label: 'Beta',
        remoteHost: '127.0.0.1',
        remotePort: 3000,
        scheme: TunnelScheme.http,
        path: '/',
      ),
    );
    await tunnels.upsert(
      TunnelTarget(
        id: 'a2',
        hostId: hostId,
        label: 'Alpha',
        remoteHost: '127.0.0.1',
        remotePort: 9090,
        scheme: TunnelScheme.https,
        path: '/',
      ),
    );
    await tunnels.upsert(
      TunnelTarget(
        id: 'a1',
        hostId: hostId,
        label: 'Alpha',
        remoteHost: '127.0.0.1',
        remotePort: 8080,
        scheme: TunnelScheme.http,
        path: '/',
      ),
    );

    final list = await tunnels.watchForHost(hostId).first;
    expect(list.map((t) => t.id).toList(), ['a1', 'a2', 'b']);
  });

  test('recordAudit persists closeReason; orphan requires it null', () async {
    await hosts.recordAudit(
      hostId: 'h1',
      hostAlias: 'web-01',
      remoteUser: 'deploy',
      title: 'Open tunnel → cockpit (9090)',
      command: 'tunnel-open',
      risk: 'mutate',
      usedSudo: false,
      closeReason: 'open',
    );

    final rows = await hosts.listAudit();
    expect(rows.single.closeReason, 'open');
    expect(rows.single.orphan, isFalse);
    expect(rows.single.exitCode, isNull);

    final orphan = AuditEvent(
      id: 'x',
      timestampUtc: DateTime.utc(2026, 9, 13),
      hostId: 'h',
      hostAlias: 'h',
      remoteUser: 'u',
      command: 'c',
      risk: 'read',
      usedSudo: false,
      durationMs: 0,
      appVersion: '0.1.0',
    );
    expect(orphan.orphan, isTrue);
  });
}
