import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/probes/journal_probe.dart';

const _facts = HostFacts(
  osId: 'rocky',
  osVersionId: '9',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.dnf,
  fw: FirewallBackend.firewalld,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

void main() {
  test('probe command never uses grep-{ or command substitution', () {
    final cmd = const JournalProbe().command(_facts);
    expect(cmd, contains('---KELOLA_J---'));
    expect(cmd, contains(journalctlOutputFields));
    expect(cmd, isNot(contains(r'out=$(')));
    expect(cmd, isNot(contains("grep -q '{'")));
    expect(cmd, isNot(contains(r'out=$(journalctl')));
  });

  test('exit 0 with JSON is plain success, not denial', () {
    const raw = '''
---KELOLA_J---
mode=plain
exit=0
---STDERR---
---STDOUT---
{"__CURSOR":"c1","__REALTIME_TIMESTAMP":"1","PRIORITY":"6","MESSAGE":"hi","SYSLOG_IDENTIFIER":"kelolatest"}
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.permissionDenied, isFalse);
    expect(page.entries, hasLength(1));
    expect(page.entries.single.message, 'hi');
  });

  test('exit 0 with empty stdout is empty filter state, not denial', () {
    const raw = '''
---KELOLA_J---
mode=plain
exit=0
---STDERR---
---STDOUT---
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.permissionDenied, isFalse);
    expect(page.entries, isEmpty);
    expect(page.emptyHint, contains('No log lines for filter'));
  });

  test('permission stderr is denied_perm', () {
    const raw = '''
---KELOLA_J---
mode=denied_perm
exit=1
---STDERR---
Permission denied
---STDOUT---
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.permissionDenied, isTrue);
  });

  test('sudo password is not collapsed into journal-unreadable', () {
    const raw = '''
---KELOLA_J---
mode=sudo_password
exit=1
---STDERR---
sudo: a password is required
---STDOUT---
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.permissionDenied, isFalse);
    expect(page.emptyHint, contains('sudo needs a password'));
    expect(page.emptyHint!.toLowerCase(), isNot(contains('usermod')));
  });

  test('other journalctl failure surfaces stderr', () {
    const raw = '''
---KELOLA_J---
mode=failed
exit=1
---STDERR---
Failed to parse timestamp
---STDOUT---
''';
    final page = const JournalProbe().parse(raw, '', 0);
    expect(page.permissionDenied, isFalse);
    expect(page.emptyHint, contains('Failed to parse timestamp'));
  });
}
