import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/session_logs/session_log.dart';

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

  test('records command output, skips empty, and isolates per host', () async {
    final a = await addHost('a');
    final b = await addHost('b');
    final t0 = DateTime.utc(2026, 9, 27, 10);
    await repo.recordSessionLog(
      a.id,
      title: '  ',
      body: 'ignored',
      now: t0,
    );
    await repo.recordSessionLog(
      a.id,
      title: '  uptime  ',
      body: '\$ uptime\nexit 0',
      now: t0,
    );
    await repo.recordSessionLog(
      a.id,
      title: 'df -h',
      body: '\$ df -h\nexit 0',
      now: t0.add(const Duration(seconds: 1)),
    );
    await repo.recordSessionLog(
      b.id,
      title: 'uptime',
      body: 'other host',
      now: t0,
    );

    final listed = await repo.listSessionLogs(a.id);
    expect(listed.map((l) => l.title), ['df -h', 'uptime']);
    expect(listed.first.body, contains('df -h'));
    expect(await repo.listSessionLogs(b.id), hasLength(1));
  });

  test('retention and bookmark survive prune; host delete clears rows', () async {
    final host = await addHost('gone');
    expect(await repo.sessionLogRetentionDays(), 14);
    await repo.setSessionLogRetentionDays(7);
    expect(await repo.sessionLogRetentionDays(), 7);

    final old = DateTime.utc(2026, 8, 1);
    await repo.recordSessionLog(
      host.id,
      title: 'old',
      body: 'stale',
      now: old,
    );
    final pinId = await repo.recordSessionLog(
      host.id,
      title: 'pin',
      body: 'keep',
      now: old,
    );
    expect(pinId, isNotNull);
    await repo.setSessionLogBookmarked(pinId!, true);

    final kept = await repo.listSessionLogs(
      host.id,
      now: DateTime.utc(2026, 9, 27),
    );
    expect(kept.map((l) => l.title), ['pin']);
    expect(kept.single.bookmarked, isTrue);

    await repo.delete(host.id);
    expect(await repo.listSessionLogs(host.id), isEmpty);
  });

  test('journal bookmark is unique per filter and deleted with the host', () async {
    final host = await addHost('logs');
    final first = await repo.saveJournalBookmark(
      hostId: host.id,
      unit: null,
      query: 'Nginx',
      scope: JournalScope.system,
      priority: 3,
      lastHour: false,
    );
    final again = await repo.saveJournalBookmark(
      hostId: host.id,
      query: 'nginx',
      scope: JournalScope.system,
      priority: 3,
      lastHour: false,
    );
    expect(again.id, first.id);
    expect(await repo.listJournalBookmarks(host.id), hasLength(1));
    expect(first.label, contains('SYSTEM'));

    await repo.deleteJournalBookmark(first.id);
    expect(await repo.listJournalBookmarks(host.id), isEmpty);

    await repo.saveJournalBookmark(
      hostId: host.id,
      query: 'sshd',
      scope: JournalScope.all,
      lastHour: true,
    );
    await repo.delete(host.id);
    expect(await repo.listJournalBookmarks(host.id), isEmpty);
  });
}
