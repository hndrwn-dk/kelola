import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';

void main() {
  test('sudoNeedsPassword is stored and reloaded', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);
    final host = await repo.insert(
      alias: 'nas-01',
      address: '192.168.1.24',
      port: 22,
      username: 'hendra',
    );
    expect(host.sudoNeedsPassword, isFalse);

    await repo.setSudoNeedsPassword(host.id, true);
    final flagged = await repo.get(host.id);
    expect(flagged!.sudoNeedsPassword, isTrue);

    await repo.setSudoNeedsPassword(host.id, false);
    final cleared = await repo.get(host.id);
    expect(cleared!.sudoNeedsPassword, isFalse);
  });
}
