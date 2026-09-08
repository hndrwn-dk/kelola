import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/facts/enums.dart';

void main() {
  late KelolaDatabase db;
  late HostRepository repo;

  setUp(() {
    db = KelolaDatabase.memory();
    repo = HostRepository(db);
  });

  tearDown(() => db.close());

  test('watchList emits when a host is inserted', () async {
    final events = <int>[];
    final sub = repo.watchList().listen((hosts) => events.add(hosts.length));
    await pumpEventQueue();
    expect(events, isNotEmpty);
    expect(events.last, 0);

    await repo.insert(
      alias: 'edge-01',
      address: '10.0.0.9',
      port: 22,
      username: 'hendra',
    );
    await pumpEventQueue();
    expect(events.last, 1);
    await sub.cancel();
  });

  test('watchList re-emits when attention changes', () async {
    final host = await repo.insert(
      alias: 'edge-01',
      address: '10.0.0.9',
      port: 22,
      username: 'hendra',
    );
    final attentions = <HostAttention>[];
    final sub = repo.watchList().listen((hosts) {
      if (hosts.isNotEmpty) {
        attentions.add(hosts.first.attention);
      }
    });
    await pumpEventQueue();
    final before = attentions.length;

    await repo.updateAttention(
      id: host.id,
      attention: HostAttention.failedUnits,
      attentionAt: DateTime.now().toUtc(),
      failedUnitCount: 1,
    );
    await pumpEventQueue();
    expect(attentions.length, greaterThan(before));
    expect(attentions.last, HostAttention.failedUnits);
    await sub.cancel();
  });

  test('watchLastHostId emits after setLastHost', () async {
    final host = await repo.insert(
      alias: 'edge-01',
      address: '10.0.0.9',
      port: 22,
      username: 'hendra',
    );
    final ids = <String?>[];
    final sub = repo.watchLastHostId().listen(ids.add);
    await pumpEventQueue();
    await repo.setLastHost(host.id);
    await pumpEventQueue();
    expect(ids, contains(host.id));
    await sub.cancel();
  });

  test('watchRecentHosts emits after touchRecent', () async {
    final host = await repo.insert(
      alias: 'edge-01',
      address: '10.0.0.9',
      port: 22,
      username: 'hendra',
    );
    final counts = <int>[];
    final sub = repo.watchRecentHosts().listen((h) => counts.add(h.length));
    await pumpEventQueue();
    await repo.touchRecent(host);
    await pumpEventQueue();
    expect(counts.last, 1);
    await sub.cancel();
  });
}
