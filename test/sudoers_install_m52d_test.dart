import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';

/// M52d: the one tap also adds the login to systemd-journal and folds the
/// old per-action `kelola-units` lines into the main file. These run the real
/// script against a fake `sudo` that maps `/etc/sudoers.d/` to a temp dir.
void main() {
  const user = 'hendr';
  const content =
      '# Kelola — managed sudoers drop-in\n'
      '\n'
      'hendr ALL=(root) NOPASSWD: /usr/sbin/reboot ""\n';

  group('script text', () {
    test('without a login the script is the plain install', () {
      final plain = buildSudoersInstallScript(content: content);
      expect(plain, isNot(contains('usermod')));
      expect(plain, isNot(contains(kelolaUnitSudoersPath)));
      expect(
        buildSudoersInstallScript(
          content: content,
          user: 'bad user',
          retireUnits: true,
          journalGroup: true,
        ),
        plain,
      );
      expect(
        buildSudoersInstallScript(
          content: content,
          user: '-o',
          journalGroup: true,
        ),
        plain,
      );
    });

    test('the group and the fold come after visudo and the install', () {
      final s = buildSudoersInstallScript(
        content: content,
        user: user,
        retireUnits: true,
        journalGroup: true,
      );
      expect(s.toLowerCase(), isNot(contains('password')));
      final visudo = s.indexOf('visudo -c -f');
      final install = s.indexOf(' install -o root');
      // Lines are folded into the temp file before visudo checks it.
      expect(s.indexOf(kelolaUnitSudoersPath), lessThan(visudo));
      expect(s.indexOf('rm -f --'), greaterThan(install));
      expect(s.indexOf('usermod -aG'), greaterThan(install));
      expect(
        s.indexOf('usermod -aG'),
        greaterThan(s.indexOf(sudoersInstallOkMarker)),
      );
      // Only this one group, never a group name from the host.
      expect(
        RegExp(r'usermod -aG (\S+)').firstMatch(s)!.group(1),
        kelolaJournalGroup,
      );
    });

    test('the probe audit names what the tap also did', () {
      final spec = KelolaSudoersSpec(
        user: user,
        groups: const {},
        commands: const [],
      );
      final probe = SudoersInstallProbe(
        spec: spec,
        groupsLabel: 'x',
        user: user,
        retireUnits: true,
        journalGroup: true,
      );
      final audit = probe.auditCommand(HostFacts.undiscovered);
      expect(audit, contains('retire=$kelolaUnitSudoersPath'));
      expect(audit, contains('group=$kelolaJournalGroup'));
    });

    test('parse reads the journal group and retire markers', () {
      SudoersInstallResult parse(String after) => parseSudoersInstallOutput(
        stdout: '$content$sudoersInstallOkMarker\n$after',
        stderr: '',
        exitCode: 0,
        expectedContent: content,
      );
      expect(parse('').journalGroup, JournalGroupOutcome.notAsked);
      expect(parse('').unitsRetired, isFalse);
      expect(
        parse('${sudoersJournalGroupMarker}added\n').journalGroup,
        JournalGroupOutcome.added,
      );
      expect(
        parse('${sudoersJournalGroupMarker}member\n').journalGroup,
        JournalGroupOutcome.member,
      );
      expect(
        parse('${sudoersJournalGroupMarker}nogroup\n').journalGroup,
        JournalGroupOutcome.noGroup,
      );
      expect(
        parse('${sudoersJournalGroupMarker}???\n').journalGroup,
        JournalGroupOutcome.failed,
      );
      expect(parse('$sudoersUnitsRetiredMarker\n').unitsRetired, isTrue);
      // A marker before the OK line (in the file body) does not count.
      final early = parseSudoersInstallOutput(
        stdout: '$sudoersUnitsRetiredMarker\n$content$sudoersInstallOkMarker\n',
        stderr: '',
        exitCode: 0,
        expectedContent: content,
      );
      expect(early.unitsRetired, isFalse);
    });

    test('the fold matches only this login\'s old grant lines', () {
      final re = RegExp('^${unitGrantLineRegex(user)}\$');
      for (final ok in [
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl reload getty@tty1.service',
        r'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl stop a\:b.service',
      ]) {
        expect(re.hasMatch(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'hendrx ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service',
        'other ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl enable nginx.service',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart *',
        'hendr ALL=(root) NOPASSWD: ALL',
        'hendr ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx.service',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart a b',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart -H x',
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx, /bin/sh',
      ]) {
        expect(re.hasMatch(bad), isFalse, reason: bad);
      }
      // A dot in the login is literal.
      expect(
        RegExp('^${unitGrantLineRegex('a.b')}\$').hasMatch(
          'axb ALL=(root) NOPASSWD: /usr/bin/systemctl restart n.service',
        ),
        isFalse,
      );
    });
  });

  group('the script against a fake sudo', () {
    late Directory dir;
    late Directory etc;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('kelola_m52d');
      etc = Directory('${dir.path}/sudoers.d')..createSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> stub(String name, String body) async {
      File('${dir.path}/bin/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', '${dir.path}/bin/$name']);
    }

    /// Fake `sudo` (reads the password line like `sudo -S`, maps
    /// `/etc/sudoers.d/` to [etc]), `getent` and `id`.
    Future<void> stubs() async {
      await stub('sudo', r'''
while [ $# -gt 0 ]; do
  case "$1" in -S|-n) shift ;; -p) shift 2 ;; *) break ;; esac
done
IFS= read -r pw || true
[ "$pw" = s3cret ] || { echo 'bad pass' >&2; exit 1; }
cmd=$1; shift
n=$#
while [ $n -gt 0 ]; do
  a=$1; shift; n=$((n-1))
  case "$a" in /etc/sudoers.d/*) a="$ETC/${a#/etc/sudoers.d/}" ;; esac
  set -- "$@" "$a"
done
case "$cmd" in
  visudo) exit "$VISUDO_RC" ;;
  install) for last; do :; done; eval "src=\${$(($#-1))}"; cp "$src" "$last" ;;
  usermod) echo "$@" >> "$LOG"; exit "$USERMOD_RC" ;;
  *) exec "$cmd" "$@" ;;
esac''');
      await stub('getent', r'[ "$HAS_GROUP" = 1 ]');
      await stub('id', r'echo "$GROUPS_OUT"');
    }

    setUp(stubs);

    /// Runs the script with the password on stdin. [groups] is what `id -nG`
    /// prints, [hasGroup] whether `getent group systemd-journal` finds it.
    Future<ProcessResult> run({
      bool retireUnits = true,
      bool journalGroup = true,
      String groups = 'hendr sudo',
      bool hasGroup = true,
      int usermodRc = 0,
      int visudoRc = 0,
    }) async {
      final p = await Process.start(
        'sh',
        [
          '-c',
          buildSudoersInstallScript(
            content: content,
            user: user,
            retireUnits: retireUnits,
            journalGroup: journalGroup,
          ),
        ],
        environment: {
          'PATH': '${dir.path}/bin:/usr/bin:/bin',
          'ETC': etc.path,
          'LOG': '${dir.path}/usermod.log',
          'GROUPS_OUT': groups,
          'HAS_GROUP': hasGroup ? '1' : '0',
          'USERMOD_RC': '$usermodRc',
          'VISUDO_RC': '$visudoRc',
        },
      );
      p.stdin.writeln('s3cret');
      await p.stdin.close();
      final out = await p.stdout.transform(systemEncoding.decoder).join();
      final err = await p.stderr.transform(systemEncoding.decoder).join();
      return ProcessResult(p.pid, await p.exitCode, out, err);
    }

    File units() => File('${etc.path}/kelola-units');
    File main() => File('${etc.path}/kelola');
    String usermodLog() {
      final f = File('${dir.path}/usermod.log');
      return f.existsSync() ? f.readAsStringSync() : '';
    }

    final skip = Platform.isWindows ? 'needs a POSIX sh and chmod' : null;

    test('moves this login\'s service lines in and removes kelola-units', () async {
      units().writeAsStringSync(
        '# Kelola: one service action per line. Safe to edit.\n'
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n'
        'hendr ALL=(root) NOPASSWD: /usr/sbin/reboot ""\n'
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl reload a\\:b.service\n',
      );
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      // The folded lines follow the expected content; verify still passes.
      final result = parseSudoersInstallOutput(
        stdout: r.stdout as String,
        stderr: r.stderr as String,
        exitCode: r.exitCode,
        expectedContent: content,
      );
      expect(result.ok, isTrue, reason: result.errorSummary);
      expect(
        result.unitsRetired,
        isFalse,
        reason: 'the reboot line is not a service line, so the file stays',
      );
      expect(units().existsSync(), isTrue);
      final installed = main().readAsStringSync();
      expect(installed, startsWith(content));
      expect(
        installed,
        contains(
          'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n',
        ),
      );
      expect(installed, contains(r'/usr/bin/systemctl reload a\:b.service'));
      // The reboot line was already in the content: not added twice.
      expect('/usr/sbin/reboot'.allMatches(installed), hasLength(1));
    }, skip: skip);

    test('removes kelola-units once every rule in it moved', () async {
      units().writeAsStringSync(
        '# Kelola: one service action per line. Safe to edit.\n'
        '\n'
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n',
      );
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains(sudoersUnitsRetiredMarker));
      expect(units().existsSync(), isFalse);
      expect(main().readAsStringSync(), contains('restart nginx.service'));
    }, skip: skip);

    test('another login\'s or a wide line keeps kelola-units, not moved', () async {
      units().writeAsStringSync(
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n'
        'alice ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n'
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart *\n',
      );
      final r = await run();
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, isNot(contains(sudoersUnitsRetiredMarker)));
      expect(units().existsSync(), isTrue);
      final installed = main().readAsStringSync();
      expect(installed, isNot(contains('alice')));
      expect(installed, isNot(contains('*')));
    }, skip: skip);

    test('a visudo failure installs nothing and removes nothing', () async {
      units().writeAsStringSync(
        'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n',
      );
      final r = await run(visudoRc: 1);
      expect(r.exitCode, isNot(0));
      expect(main().existsSync(), isFalse);
      expect(units().existsSync(), isTrue);
      expect(usermodLog(), isEmpty);
    }, skip: skip);

    test('adds the login to systemd-journal when it is not a member', () async {
      final r = await run();
      expect(r.stdout, contains('${sudoersJournalGroupMarker}added'));
      expect(usermodLog().trim(), '-aG $kelolaJournalGroup $user');
    }, skip: skip);

    test('a member, a host without the group, or a usermod failure', () async {
      var r = await run(groups: 'hendr systemd-journal');
      expect(r.stdout, contains('${sudoersJournalGroupMarker}member'));
      expect(usermodLog(), isEmpty);

      r = await run(hasGroup: false);
      expect(r.stdout, contains('${sudoersJournalGroupMarker}nogroup'));
      expect(usermodLog(), isEmpty);

      r = await run(usermodRc: 1);
      expect(r.exitCode, 0, reason: 'the main file is already installed');
      expect(r.stdout, contains('${sudoersJournalGroupMarker}failed'));
    }, skip: skip);

    test('no kelola-units and no group step when not asked', () async {
      final r = await run(retireUnits: false, journalGroup: false);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, isNot(contains(sudoersJournalGroupMarker)));
      expect(usermodLog(), isEmpty);
      expect(main().readAsStringSync(), content);
    }, skip: skip);
  });
}
