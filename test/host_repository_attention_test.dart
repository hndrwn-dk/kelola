import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/facts/enums.dart';

void main() {
  test('updateAttention stores snapshot counts without wiping them on unreachable',
      () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    expect(host.attentionAt, isNull);
    expect(host.failedUnitCount, isNull);
    expect(host.diskRootPercent, isNull);

    final at = DateTime.utc(2026, 9, 2, 8);
    await repo.updateAttention(
      id: host.id,
      attention: HostAttention.failedUnits,
      failedUnitCount: 2,
      diskRootPercent: 78,
      attentionAt: at,
    );
    final stored = await repo.get(host.id);
    expect(stored!.failedUnitCount, 2);
    expect(stored.diskRootPercent, 78);
    expect(stored.attentionAt!.isAtSameMomentAs(at), isTrue);
    expect(stored.attention, HostAttention.failedUnits);

    await repo.updateAttention(
      id: host.id,
      attention: HostAttention.unreachable,
    );
    final after = await repo.get(host.id);
    expect(after!.failedUnitCount, 2);
    expect(after.diskRootPercent, 78);
    expect(after.attentionAt!.isAtSameMomentAs(at), isTrue);
    expect(after.attention, HostAttention.unreachable);
  });
}
