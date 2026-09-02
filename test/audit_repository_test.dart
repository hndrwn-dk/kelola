import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';

void main() {
  test('beginAudit stores probe title separately from raw command', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);

    final id = await repo.beginAudit(
      hostId: 'h1',
      hostAlias: 'nas-01',
      remoteUser: 'hendra',
      title: 'Polled dashboard',
      command: 'LC_ALL=C\ncat /proc/uptime',
      risk: 'read',
      usedSudo: false,
    );
    await repo.finishAudit(id, exitCode: 0, durationMs: 42);

    final rows = await repo.listAudit();
    expect(rows, hasLength(1));
    expect(rows.first.title, 'Polled dashboard');
    expect(rows.first.command, 'LC_ALL=C\ncat /proc/uptime');
    expect(rows.first.command, isNot(equals('LC_ALL=C')));
  });

  test('legacy rows with empty title still list without crashing', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);

    await repo.recordAudit(
      hostId: 'h1',
      hostAlias: 'nas-01',
      remoteUser: 'hendra',
      command: 'LC_ALL=C',
      risk: 'read',
      usedSudo: false,
      exitCode: 0,
    );

    final rows = await repo.listAudit();
    expect(rows, hasLength(1));
    expect(rows.first.title, '');
    expect(rows.first.command, 'LC_ALL=C');
  });

  test('recordAudit stores host-key mismatch title', () async {
    final db = KelolaDatabase.memory();
    addTearDown(db.close);
    final repo = HostRepository(db);

    await repo.recordAudit(
      hostId: 'h1',
      hostAlias: 'web-prod',
      remoteUser: '',
      title: 'Host key mismatch',
      command: 'host-key-verify',
      risk: 'read',
      usedSudo: false,
      exitCode: 1,
      errorSummary: 'host key mismatch SHA256:other',
    );

    final rows = await repo.listAudit();
    expect(rows.single.title, 'Host key mismatch');
    expect(rows.single.errorSummary, contains('host key mismatch'));
  });
}
