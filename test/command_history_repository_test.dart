import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/command_history/command_history.dart';
import 'package:kelola/domain/hosts/host.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Host> addHost(String alias) {
    return repo.insert(
      alias: alias,
      address: '10.0.0.1',
      port: 22,
      username: 'hendr',
    );
  }

  test('skips empty lines and upserts unique command newest first', () async {
    final host = await addHost('east-worker');
    final t0 = DateTime.utc(2026, 9, 21, 10);
    await repo.recordCommandHistory(host.id, '   ', now: t0);
    await repo.recordCommandHistory(host.id, '  uptime  ', now: t0);
    await repo.recordCommandHistory(
      host.id,
      'df -h',
      now: t0.add(const Duration(seconds: 1)),
    );
    await repo.recordCommandHistory(
      host.id,
      'uptime',
      now: t0.add(const Duration(seconds: 2)),
    );

    expect(await repo.listCommandHistory(host.id), ['uptime', 'df -h']);
  });

  test('caps at 200 per host by oldest usedAt', () async {
    final host = await addHost('capped');
    final t0 = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < kCommandHistoryCap + 1; i++) {
      await repo.recordCommandHistory(
        host.id,
        'cmd-$i',
        now: t0.add(Duration(seconds: i)),
      );
    }
    final listed = await repo.listCommandHistory(host.id);
    expect(listed, hasLength(kCommandHistoryCap));
    expect(listed.first, 'cmd-$kCommandHistoryCap');
    expect(listed.contains('cmd-0'), isFalse);
    expect(listed.last, 'cmd-1');
  });

  test('isolates history per host and filters by substring', () async {
    final a = await addHost('a');
    final b = await addHost('b');
    final t0 = DateTime.utc(2026, 9, 21);
    await repo.recordCommandHistory(a.id, 'systemctl status nginx', now: t0);
    await repo.recordCommandHistory(
      a.id,
      'uptime',
      now: t0.add(const Duration(seconds: 1)),
    );
    await repo.recordCommandHistory(b.id, 'uptime', now: t0);

    expect(await repo.listCommandHistory(a.id, query: 'SYSTEMCTL'), [
      'systemctl status nginx',
    ]);
    expect(await repo.listCommandHistory(b.id), ['uptime']);
  });

  test('delete host removes its command history', () async {
    final host = await addHost('gone');
    await repo.recordCommandHistory(host.id, 'uptime');
    await repo.delete(host.id);
    expect(await repo.listCommandHistory(host.id), isEmpty);
  });
}
