import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/probes/journal_probe.dart';

HostFacts facts({
  required JournalAccess access,
  bool hasJournald = true,
  bool journalReadable = false,
}) {
  return HostFacts(
    osId: 'rocky',
    osVersionId: '9',
    init: InitSystem.systemd,
    systemdVersion: 252,
    pkg: PackageManager.dnf,
    fw: FirewallBackend.firewalld,
    hasJournald: hasJournald,
    journalReadable: journalReadable,
    journalAccess: access,
    arch: 'x86_64',
  );
}

void main() {
  test('plain access never emits sudo journalctl or syslog sudo', () {
    final cmd = const JournalProbe().command(
      facts(access: JournalAccess.plain, journalReadable: true),
    );
    expect(cmd, contains('journalctl'));
    expect(cmd, isNot(contains('sudo -n')));
    expect(cmd, contains('emit plain'));
  });

  test('denied access never touches the host with sudo', () {
    final cmd = const JournalProbe().command(facts(access: JournalAccess.denied));
    expect(cmd, isNot(contains('sudo -n')));
    expect(cmd, contains('denied_perm'));
    expect(cmd, isNot(contains('journalctl -o json --no-pager -n')));
  });

  test('sudo access uses sudo only — no plain-then-escalate ladder', () {
    final cmd = const JournalProbe().command(
      facts(access: JournalAccess.sudo, journalReadable: true),
    );
    expect(cmd, contains('sudo -n journalctl'));
    expect(cmd, isNot(contains('emit plain')));
    // One sudo journalctl invocation in the script body (not a probe ladder).
    expect('sudo -n journalctl'.allMatches(cmd).length, 1);
  });

  test('unknown access may try sudo once after plain fails', () {
    final cmd = const JournalProbe().command(facts(access: JournalAccess.unknown));
    expect(cmd, contains('sudo -n journalctl'));
  });

  test('parse modes publish learnedAccess for caching', () {
    expect(
      const JournalProbe()
          .parse(
            '---KELOLA_J---\nmode=plain\nexit=0\n---STDERR---\n---STDOUT---\n',
            '',
            0,
          )
          .learnedAccess,
      JournalAccess.plain,
    );
    expect(
      const JournalProbe()
          .parse(
            '---KELOLA_J---\nmode=sudo\nexit=0\n---STDERR---\n---STDOUT---\n',
            '',
            0,
          )
          .learnedAccess,
      JournalAccess.sudo,
    );
    expect(
      const JournalProbe()
          .parse(
            '---KELOLA_J---\nmode=sudo_password\nexit=1\n---STDERR---\n'
            'sudo: a password is required\n---STDOUT---\n',
            '',
            0,
          )
          .learnedAccess,
      JournalAccess.denied,
    );
    expect(
      const JournalProbe()
          .parse(
            '---KELOLA_J---\nmode=denied_perm\nexit=1\n---STDERR---\n'
            'Permission denied\n---STDOUT---\n',
            '',
            0,
          )
          .learnedAccess,
      JournalAccess.denied,
    );
  });

  test('readable facts default to plain effective access (no sudo ladder)', () {
    final cmd = const JournalProbe().command(
      facts(access: JournalAccess.unknown, journalReadable: true),
    );
    expect(cmd, isNot(contains('sudo -n')));
  });

  test('syslog script omits sudo legs when access is plain or denied', () {
    expect(syslogSelectPathScript(JournalAccess.plain), isNot(contains('sudo')));
    expect(syslogSelectPathScript(JournalAccess.denied), isNot(contains('sudo')));
    expect(syslogSelectPathScript(JournalAccess.unknown), contains('sudo -n test -r'));
  });

  test('syslog unknown with no readable path learns denied (sudo tried once)', () {
    final page = const JournalProbe().parse(
      '---NOSYSLOG---\nkelola_access=denied\n',
      '',
      0,
    );
    expect(page.learnedAccess, JournalAccess.denied);
    expect(page.noReadableLogSource, isTrue);
  });

  test('follow respects cached access — denied never sudo', () {
    final denied = const JournalFollowCommand().command(
      facts(access: JournalAccess.denied),
    );
    expect(denied, isNot(contains('sudo -n')));
    expect(denied, contains('---DENIED---'));

    final plain = const JournalFollowCommand().command(
      facts(access: JournalAccess.plain, journalReadable: true),
    );
    expect(plain, isNot(contains('sudo -n')));
    expect(plain, contains('journalctl -o json --no-pager -f'));
  });

  test('coalesce keeps denied/sudo across HostFacts rediscovery', () {
    final previous = facts(access: JournalAccess.denied);
    final incoming = facts(access: JournalAccess.unknown);
    final merged = coalesceJournalAccess(incoming, previous);
    expect(merged.journalAccess, JournalAccess.denied);

    final upgraded = coalesceJournalAccess(
      facts(access: JournalAccess.plain, journalReadable: true),
      previous,
    );
    expect(upgraded.journalAccess, JournalAccess.plain);
  });
}
