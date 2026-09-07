import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/probes/journal_probe.dart';

const _journaled = HostFacts(
  osId: 'debian',
  osVersionId: '12',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.apt,
  fw: FirewallBackend.ufw,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

const _alpine = HostFacts(
  osId: 'alpine',
  osVersionId: '3.20',
  init: InitSystem.openrc,
  systemdVersion: null,
  pkg: PackageManager.apk,
  fw: FirewallBackend.nftables,
  hasJournald: false,
  journalReadable: false,
  arch: 'x86_64',
);

void main() {
  test('kicker string matches journalctl scope flags (asserted together)', () {
    const cases = <(JournalScope, String, String)>[
      (JournalScope.all, 'ALL JOURNALS · ALL', ''),
      (JournalScope.system, 'SYSTEM · ALL', ' --system'),
      (JournalScope.user, 'USER · ALL', ' --user'),
    ];
    for (final (scope, kicker, flag) in cases) {
      final filters = journalctlFilters(scope: scope);
      expect(
        (journalKicker(scope: scope), filters),
        (kicker, flag),
        reason: 'scope=$scope',
      );
      expect(filters.contains('--system'), scope == JournalScope.system);
      expect(filters.contains('--user'), scope == JournalScope.user);
    }
    expect(
      (
        journalKicker(unit: 'nginx.service', priority: 3, scope: JournalScope.all),
        journalctlFilters(unit: 'nginx.service', priority: 3, scope: JournalScope.all),
      ),
      ('NGINX.SERVICE · ERR+', " -u 'nginx.service' -p 3"),
    );
    expect(journalKicker(syslog: true), 'SYSLOG · ALL');
  });

  for (final scope in JournalScope.values) {
    test('live and historical share identical filters for scope=$scope', () {
      final filters = journalctlFilters(scope: scope);
      final follow = JournalFollowCommand(scope: scope).command(_journaled);
      final historical = JournalProbe(scope: scope).command(_journaled);

      expect(follow, contains('journalctl -o json --no-pager -f -n 0'));
      expect(follow, contains(filters));
      expect(historical, contains('journalctl -o json --no-pager -n 200'));
      expect(historical, contains(filters));
      expect(historical, contains('---KELOLA_J---'));
      expect(historical, isNot(contains("grep -q '{'")));
      expect(historical, isNot(contains(r'out=$(')));
      expect(follow.contains('--system'), historical.contains('--system'));
      expect(follow.contains('--user'), historical.contains('--user'));
      expect(follow, isNot(contains('tail -n 0 -F /var/log/syslog')));
      expect(historical, isNot(contains('tail -n 200')));
    });
  }

  test('without journald, historical and live use the same syslog probe order',
      () {
    final follow = const JournalFollowCommand().command(_alpine);
    final historical = const JournalProbe().command(_alpine);
    for (final path in syslogProbePaths) {
      expect(follow, contains(path));
      expect(historical, contains(path));
    }
    expect(follow, contains('tail -n 0 -F'));
    expect(historical, contains('tail -n 200'));
    expect(follow, contains('---NOSYSLOG---'));
    expect(historical, contains('---NOSYSLOG---'));
    expect(follow, isNot(contains('journalctl')));
    expect(historical, isNot(contains('journalctl')));
  });

  test('syslog historical parse marks usedSyslog and yields logger lines', () {
    const raw = '''
---SYSLOG---
2026-09-03T06:55:32.661499+00:00 east-worker-uat kelolatest: cobain 1
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.hasJournald, isFalse);
    expect(page.usedSyslog, isTrue);
    expect(page.noReadableLogSource, isFalse);
    expect(page.entries, hasLength(1));
    expect(page.entries.single.message, contains('cobain'));
  });

  test('neither journald nor syslog is an honest empty state', () {
    final page = const JournalProbe().parse('---NOSYSLOG---\n', '', 0);
    expect(page.noReadableLogSource, isTrue);
    expect(page.entries, isEmpty);
    expect(page.emptyHint, contains('/var/log/syslog'));
  });
}
