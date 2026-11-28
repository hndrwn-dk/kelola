import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/kelola_sudo_files.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';

// Host details → Kelola sudo rules: see and remove the lines Kelola wrote.

const _facts = HostFacts(
  osId: 'ubuntu',
  osVersionId: '24.04',
  init: InitSystem.systemd,
  systemdVersion: 255,
  pkg: PackageManager.apt,
  fw: FirewallBackend.ufw,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

const _p = 'hendr ALL=(root) NOPASSWD: ';

Map<String, String> _captures() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/sudoers/sudo_list_captures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      e.key: (e.value as Map<String, dynamic>)['stdout'] as String,
  };
}

String _b64(String s) => base64Encode(utf8.encode(s));

void main() {
  group('the files Kelola writes', () {
    test('are exactly the Enable file, kelola-units and kelola-web', () {
      expect(kelolaOwnedSudoersFiles, [
        kelolaSudoersPath,
        kelolaUnitSudoersPath,
        kelolaWebSudoersPath,
      ]);
      expect(kelolaOwnedSudoersFiles, [
        '/etc/sudoers.d/kelola',
        '/etc/sudoers.d/kelola-units',
        '/etc/sudoers.d/kelola-web',
      ]);
    });

    test('rule lines skip blanks and comments, keep include directives', () {
      expect(isSudoersRuleLine('$_p/usr/sbin/reboot ""'), isTrue);
      expect(isSudoersRuleLine(''), isFalse);
      expect(isSudoersRuleLine('   '), isFalse);
      expect(isSudoersRuleLine('# Kelola — managed sudoers drop-in'), isFalse);
      // Directives, not comments: a file with one is never "empty".
      expect(isSudoersRuleLine('#include /etc/x'), isTrue);
      expect(isSudoersRuleLine('#includedir /etc/y'), isTrue);
      expect(isSudoersRuleLine('@include /etc/z'), isTrue);
    });
  });

  group('sudo -n -l', () {
    test('classic 1.9.15: NOPASSWD commands, escapes removed, merged lines split', () {
      final c = parseSudoListingCommands(_captures()['classic-1.9.15']!);
      expect(c, [
        '/usr/sbin/reboot ""',
        '/usr/sbin/poweroff ""',
        '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold upgrade',
        '/usr/bin/systemctl reload nginx.service',
        '/usr/sbin/sysctl -w vm.drop_caches=3',
        '/usr/sbin/nginx -t',
        '/usr/bin/tail -n 60 /var/log/nginx/error.log',
        '/opt/backup/run.sh',
      ]);
    });

    test('classic 1.9.9 prints "" as \\"\\"', () {
      expect(parseSudoListingCommands(_captures()['classic-1.9.9']!), [
        '/usr/sbin/reboot ""',
        '/usr/bin/systemctl restart mariadb.service',
      ]);
    });

    test('sudo-rs: the same shape; password rules are left out', () {
      expect(parseSudoListingCommands(_captures()['sudo-rs-0.2']!), [
        '/usr/sbin/reboot ""',
        '/usr/bin/systemctl start mariadb.service',
        '/usr/bin/systemctl stop mariadb.service',
      ]);
    });

    test('junk and empty input give nothing', () {
      expect(parseSudoListingCommands(''), isEmpty);
      expect(parseSudoListingCommands('sudo: a password is required\n'), isEmpty);
      expect(parseSudoListingCommands('NOPASSWD:\n  NOPASSWD:   \n'), isEmpty);
    });

    test('only commands Kelola could have written count as Kelola rules', () {
      final c = parseSudoListingCommands(_captures()['classic-1.9.15']!);
      expect(c.where(isKelolaSudoCommand), hasLength(7));
      expect(isKelolaSudoCommand('/opt/backup/run.sh'), isFalse);
      expect(isKelolaSudoCommand('/usr/local/bin/systemctl reload x'), isFalse);
      expect(isKelolaSudoCommand('ALL'), isFalse);
      // Old refusals and wide rules of Kelola's own binaries still count,
      // so a host whose files need the password shows them.
      expect(isKelolaSudoCommand('!/usr/bin/systemctl'), isTrue);
      expect(isKelolaSudoCommand('/usr/bin/apt-get install *'), isTrue);
    });
  });

  group('plain words', () {
    final cases = <String, String>{
      '/usr/bin/systemctl reload nginx.service': 'Reload nginx.service',
      '/usr/bin/systemctl start mariadb.service': 'Start mariadb.service',
      '/usr/bin/systemctl stop redis-server.service':
          'Stop redis-server.service',
      '/usr/bin/systemctl restart dbus-org.freedesktop\\:1.service':
          'Restart dbus-org.freedesktop:1.service',
      r'/usr/bin/systemctl ^(start|stop|restart|reload) [a-zA-Z0-9][a-zA-Z0-9\:_.@-]*$':
          'Start, stop, restart or reload any service (old rule)',
      '/usr/sbin/reboot ""': 'Reboot the host',
      '/usr/sbin/poweroff ""': 'Power off the host',
      '/usr/sbin/sysctl -w vm.drop_caches=3': 'Flush caches',
      '/usr/bin/kill ^-s (TERM|KILL) ([2-9]|[1-9][0-9][0-9]?)\$':
          'Send TERM or KILL to a process',
      '/usr/bin/docker info': 'Read Docker status',
      '/usr/bin/docker ps -a --format {{json .}}': 'List Docker containers',
      '/usr/bin/docker ^logs --tail (60|2000) [A-Za-z0-9][A-Za-z0-9_.-]*\$':
          'Read a container\'s recent logs',
      '/usr/bin/dnf --color=never check-update --refresh':
          'Check for package updates',
      '/usr/bin/dnf upgrade -y': 'Upgrade all packages',
      '/usr/bin/dnf upgrade -y --security': 'Install security updates',
      '/usr/bin/dnf ^upgrade -y [a-z]+\$': 'Upgrade one package',
      r'/usr/bin/apt-get -y -o Dpkg\:\:Options\:\:=--force-confold upgrade':
          'Upgrade all packages',
      '/usr/bin/firewall-cmd --list-all': 'Read firewall rules',
      '/usr/bin/firewall-cmd --reload': 'Reload the firewall',
      '/usr/sbin/ufw status verbose': 'Read firewall rules',
      '/usr/sbin/ufw ^(delete )?allow [0-9]+(/(tcp|udp))?\$':
          'Open or close a firewall port',
      '/usr/sbin/iptables-save ""': 'Read firewall rules',
      '/usr/bin/test -r /var/log/syslog': 'Check /var/log/syslog is readable',
      '/usr/bin/tail -n 200 /var/log/syslog':
          'Read the last 200 lines of /var/log/syslog',
      '/usr/bin/tail -n 0 -F /var/log/syslog': 'Follow /var/log/syslog',
      '/usr/sbin/nginx -t': 'Test the nginx config',
      '/usr/sbin/nginx -T': 'Print the nginx config',
      '/usr/sbin/apachectl -t': 'Test the Apache config',
      '/usr/sbin/apachectl -S': 'Print the Apache vhosts',
      '/usr/bin/openssl x509 -noout -enddate -subject -ext subjectAltName -in /etc/ssl/a.pem':
          'Read certificate /etc/ssl/a.pem',
      // No arguments in a rule means any arguments.
      '/opt/backup/run.sh':
          'Run /opt/backup/run.sh with any arguments as root',
      '/opt/backup/run.sh --daily': 'Run /opt/backup/run.sh --daily as root',
      '!/opt/x': 'Blocks /opt/x for this login, even with a password',
      // Shapes earlier Kelola versions wrote (see kelolaSudoRulesOutdated).
      '!/usr/bin/systemctl': 'Blocks /usr/bin/systemctl for this login, '
          'even with a password (old rule)',
      '!/usr/bin/systemctl enable *': 'Blocks /usr/bin/systemctl enable * '
          'for this login, even with a password (old rule)',
      '/usr/bin/systemctl': 'Run /usr/bin/systemctl with any arguments as '
          'root (old rule)',
      '/usr/bin/apt-get install *': 'Run /usr/bin/apt-get install with any '
          'arguments as root (old rule)',
      'ALL': 'Run any command as root',
    };
    cases.forEach((cmd, words) {
      test(words, () {
        expect(describeKelolaSudoRule(cmd), words);
        // A full file line reads the same as its command.
        expect(describeKelolaSudoRule('$_p$cmd'), words);
      });
    });

    test('the command of a file line drops the login and tags', () {
      expect(
        kelolaSudoRuleCommand('$_p/usr/sbin/nginx -t'),
        '/usr/sbin/nginx -t',
      );
      expect(kelolaSudoRuleCommand('/usr/sbin/nginx -t'), '/usr/sbin/nginx -t');
    });
  });

  group('read probe', () {
    String out({
      List<(String, String, String, List<String>)> files = const [],
      List<String>? list,
    }) => [
      for (final (path, state, read, lines) in files) ...[
        '---KFILE---',
        '@path=$path',
        '@state=$state',
        '@read=$read',
        for (final l in lines) '|$l',
      ],
      '---LIST---',
      for (final l in list ?? const <String>[]) '|$l',
    ].join('\n');

    test('is read-only and never needs the password unless asked', () {
      const p = KelolaSudoFilesProbe();
      expect(p.risk, RiskLevel.read);
      expect(p.needsSudo, isFalse);
      final cmd = p.command(_facts);
      for (final f in kelolaOwnedSudoersFiles) {
        expect(cmd, contains("'$f'"));
      }
      expect(cmd, isNot(contains('sudo -S')));
      expect(cmd, contains('sudo -n -l'));
      const pw = KelolaSudoFilesProbe(withPassword: true);
      expect(pw.risk, RiskLevel.read);
      expect(pw.needsSudo, isTrue);
      expect(pw.command(_facts), contains("sudo -S -p ''"));
      expect(pw.command(_facts), isNot(contains('sudo -n cat')));
    });

    test('readable, unreadable, absent and unknown files', () {
      final r = const KelolaSudoFilesProbe().parse(
        out(
          files: [
            (
              kelolaSudoersPath,
              'present',
              '1',
              ['# Kelola — managed sudoers drop-in', '', '$_p/usr/sbin/reboot ""'],
            ),
            (kelolaUnitSudoersPath, 'absent', '0', []),
            (kelolaWebSudoersPath, 'present', '0', []),
          ],
          list: ['    (root) NOPASSWD: /usr/sbin/reboot ""'],
        ),
        '',
        0,
      );
      expect(r.files.map((f) => f.path), kelolaOwnedSudoersFiles);
      expect(r.files[0].state, KelolaSudoFileState.present);
      expect(r.files[0].lines, ['$_p/usr/sbin/reboot ""']);
      expect(r.files[1].state, KelolaSudoFileState.absent);
      expect(r.files[2].state, KelolaSudoFileState.present);
      expect(r.files[2].lines, isNull);
      expect(r.contentsNeedPassword, isTrue);
      expect(r.listed, ['/usr/sbin/reboot ""']);
      expect(r.shown.map((f) => f.path), [kelolaSudoersPath, kelolaWebSudoersPath]);
    });

    test('unknown when the directory cannot be searched', () {
      final r = const KelolaSudoFilesProbe().parse(
        out(files: [(kelolaWebSudoersPath, 'unknown', '0', [])]),
        '',
        0,
      );
      expect(r.files.single.state, KelolaSudoFileState.unknown);
      expect(r.contentsNeedPassword, isTrue);
    });

    test('host text cannot add a file or forge a marker', () {
      final r = const KelolaSudoFilesProbe().parse(
        [
          '---KFILE---',
          '@path=/etc/sudoers.d/90-cloud-init-users',
          '@state=present',
          '@read=1',
          '|root ALL=(ALL) ALL',
          '---KFILE---',
          '@path=$kelolaSudoersPath',
          '@state=present',
          '@read=1',
          '|---KFILE---',
          '|@path=/etc/sudoers',
          '|$_p/usr/sbin/reboot ""',
          '---LIST---',
        ].join('\n'),
        '',
        0,
      );
      expect(r.files.map((f) => f.path), [kelolaSudoersPath]);
      expect(r.files.single.lines, [
        '---KFILE---',
        '@path=/etc/sudoers',
        '$_p/usr/sbin/reboot ""',
      ]);
    });

    test('a refused password says so', () {
      expect(
        () => const KelolaSudoFilesProbe(
          withPassword: true,
        ).parse('@auth=fail\n', '', 4),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            'The sudo password was not accepted.',
          ),
        ),
      );
    });
  });

  group('remove probe', () {
    test('is destructive, needs the password, and only takes the three files', () {
      for (final f in kelolaOwnedSudoersFiles) {
        final p = KelolaSudoRemoveProbe(path: f);
        expect(p.risk, RiskLevel.destructive);
        expect(p.needsSudo, isTrue);
      }
      for (final bad in [
        '/etc/sudoers',
        '/etc/sudoers.d/90-cloud-init-users',
        '/etc/sudoers.d/kelola-units2',
        '/etc/sudoers.d/kelola*',
        '/etc/sudoers.d/../sudoers',
        '/etc/sudoers.d/',
      ]) {
        expect(
          () => KelolaSudoRemoveProbe(path: bad),
          throwsArgumentError,
          reason: bad,
        );
      }
    });

    test('the script names only its own file, the line travels base64', () {
      const line = '$_p/usr/bin/systemctl reload nginx.service';
      final p = KelolaSudoRemoveProbe(path: kelolaSudoersPath, line: line);
      final cmd = p.command(_facts);
      expect(cmd, contains("'$kelolaSudoersPath'"));
      for (final other in [kelolaUnitSudoersPath, kelolaWebSudoersPath]) {
        expect(cmd, isNot(contains(other)));
      }
      expect(cmd, isNot(contains('nginx.service')));
      expect(cmd, contains(_b64(line)));
      // Never a glob over the directory.
      expect(cmd, isNot(contains('sudoers.d/*')));
      expect(cmd, isNot(contains('sudoers.d/?')));
      expect(cmd, isNot(contains('sudoers.d/[')));
      expect(cmd, contains('visudo -c -f'));
      expect(cmd.indexOf('visudo -c -f'), lessThan(cmd.indexOf('install -o root -g root -m')));
      expect(cmd, contains("-m '$kelolaSudoersMode'"));
      // The password only ever arrives on stdin.
      expect(cmd, startsWith('set -eu\nIFS= read -r SUDO_PASS'));
    });

    test('a line with a newline is refused', () {
      expect(
        () => KelolaSudoRemoveProbe(path: kelolaSudoersPath, line: 'a\nb'),
        throwsArgumentError,
      );
    });

    test('audit names the file and whether it was a line', () {
      expect(
        KelolaSudoRemoveProbe(path: kelolaWebSudoersPath).auditTitle,
        'Removed $kelolaWebSudoersPath',
      );
      expect(
        KelolaSudoRemoveProbe(
          path: kelolaWebSudoersPath,
          line: '$_p/usr/sbin/nginx -t',
        ).auditTitle,
        'Removed a line from $kelolaWebSudoersPath',
      );
    });

    test('parse: removed, file deleted, gone, line missing, link refused', () {
      final p = KelolaSudoRemoveProbe(path: kelolaSudoersPath);
      expect(p.parse('$kelolaSudoRemoveOkMarker\n@deleted=0\n', '', 0).deleted, isFalse);
      expect(p.parse('$kelolaSudoRemoveOkMarker\n@deleted=1\n', '', 0).deleted, isTrue);
      expect(p.parse('$kelolaSudoRemoveGoneMarker\n', '', 0).deleted, isTrue);
      expect(
        () => p.parse('$kelolaSudoRemoveMissingMarker\n', '', 3),
        throwsA(isA<KelolaException>()),
      );
      expect(
        () => p.parse('$kelolaSudoRemoveLinkMarker\n', '', 3),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            contains('is a symlink'),
          ),
        ),
      );
      expect(
        () => p.parse('', 'visudo: parse error', 1),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            'visudo: parse error',
          ),
        ),
      );
    });
  });

  _realTrees();
}

/// The remove and read scripts against stub trees under dash and busybox sh.
/// Linux only, like the web grant gate tests.
void _realTrees() {
  final hasDash =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v dash']).exitCode == 0;

  group('remove script (real trees)', skip: Platform.isWindows, () {
    String? bbDir;
    late Directory dir;
    late Directory d;
    late Directory bin;
    late File log;
    File f(String name) => File('${d.path}/$name');

    setUpAll(() {
      final which = Process.runSync('sh', ['-c', 'command -v busybox']);
      final bb = (which.stdout as String).trim();
      if (which.exitCode != 0 || bb.isEmpty) return;
      final t = Directory.systemTemp.createTempSync('kelola_bb');
      final r = Process.runSync(bb, ['--install', '-s', t.path]);
      if (r.exitCode == 0 && File('${t.path}/find').existsSync()) {
        bbDir = t.path;
      } else {
        t.deleteSync(recursive: true);
      }
    });

    tearDownAll(() {
      final t = bbDir;
      if (t != null) Directory(t).deleteSync(recursive: true);
    });

    /// [visudoOk] false makes `visudo -c` fail.
    void stubs({bool visudoOk = true}) {
      void stub(String name, String body) {
        File('${bin.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
        Process.runSync('chmod', ['755', '${bin.path}/$name']);
      }

      // Maps /etc/sudoers.d/<name> into the stub tree and logs each argv.
      stub('sudo', '''
[ "\$1" = -S ] || exit 9
shift 3
IFS= read -r pw
[ "\$pw" = pw ] || exit 1
for a; do
  shift
  case "\$a" in /etc/sudoers.d/*) a=${d.path}/\${a#/etc/sudoers.d/} ;; esac
  set -- "\$@" "\$a"
done
echo "\$*" >> ${log.path}
exec "\$@"''');
      stub('visudo', visudoOk ? 'exit 0' : 'echo "parse error" >&2; exit 1');
      stub('install', '''
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');
    }

    setUp(() {
      if (Platform.isWindows) return;
      dir = Directory.systemTemp.createTempSync('kelola_rm');
      d = Directory('${dir.path}/sudoers.d')..createSync();
      bin = Directory('${dir.path}/bin')..createSync();
      log = File('${dir.path}/calls.log');
      stubs();
      f('kelola').writeAsStringSync(
        '# Kelola — managed sudoers drop-in\n'
        '\n'
        '$_p/usr/sbin/reboot ""\n'
        '$_p/usr/bin/systemctl reload nginx.service\n',
      );
      f('kelola-web').writeAsStringSync(
        '# Kelola: lens read rules, one command per line. Safe to edit.\n'
        '$_p/usr/sbin/nginx -t\n',
      );
      f('90-cloud-init-users').writeAsStringSync('root ALL=(ALL) ALL\n');
    });

    tearDown(() {
      if (!Platform.isWindows) dir.deleteSync(recursive: true);
    });

    Future<ProcessResult> run(KelolaSudoRemoveProbe p, String shell) async {
      final path = shell == 'busybox'
          ? '${bin.path}:$bbDir'
          : '${bin.path}:/usr/bin:/bin';
      final s = p.command(_facts);
      final argv = shell == 'busybox'
          ? ['busybox', 'sh', '-c', s]
          : ['dash', '-c', s];
      final proc = await Process.start('env', ['PATH=$path', ...argv]);
      proc.stdin.write('pw\n');
      await proc.stdin.close();
      final out = await proc.stdout.transform(utf8.decoder).join();
      final err = await proc.stderr.transform(utf8.decoder).join();
      return ProcessResult(proc.pid, await proc.exitCode, out, err);
    }

    bool go(String shell) {
      if (shell == 'busybox' && bbDir == null) {
        markTestSkipped('busybox is not installed here');
        return false;
      }
      if (shell == 'dash' && !hasDash) {
        markTestSkipped('dash is not installed here');
        return false;
      }
      return true;
    }

    /// Every argv the stub sudo saw names only [allowed] (mapped) or temp
    /// files, never another file in sudoers.d.
    void expectOnlyTouched(List<String> allowed) {
      for (final call in log.existsSync() ? log.readAsLinesSync() : []) {
        for (final word in call.split(' ')) {
          if (!word.startsWith(d.path)) continue;
          expect(
            allowed.map((n) => '${d.path}/$n'),
            contains(word),
            reason: call,
          );
        }
      }
    }

    for (final shell in const ['dash', 'busybox']) {
      test('$shell: one line removed, the others kept', () async {
        if (!go(shell)) return;
        final before90 = f('90-cloud-init-users').readAsStringSync();
        final p = KelolaSudoRemoveProbe(
          path: kelolaSudoersPath,
          line: '$_p/usr/bin/systemctl reload nginx.service',
        );
        final r = await run(p, shell);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(p.parse(r.stdout as String, r.stderr as String, r.exitCode).deleted, isFalse);
        expect(f('kelola').readAsStringSync(),
            '# Kelola — managed sudoers drop-in\n\n$_p/usr/sbin/reboot ""\n');
        expect(f('kelola-web').existsSync(), isTrue);
        expect(f('90-cloud-init-users').readAsStringSync(), before90);
        expectOnlyTouched(['kelola']);
      });

      test('$shell: the last line deletes the file', () async {
        if (!go(shell)) return;
        final p = KelolaSudoRemoveProbe(
          path: kelolaWebSudoersPath,
          line: '$_p/usr/sbin/nginx -t',
        );
        final r = await run(p, shell);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(p.parse(r.stdout as String, r.stderr as String, r.exitCode).deleted, isTrue);
        expect(f('kelola-web').existsSync(), isFalse);
        expect(f('kelola').existsSync(), isTrue);
        expect(f('90-cloud-init-users').existsSync(), isTrue);
        expectOnlyTouched(['kelola-web']);
      });

      test('$shell: a whole file is deleted, nothing else', () async {
        if (!go(shell)) return;
        final p = KelolaSudoRemoveProbe(path: kelolaSudoersPath);
        final r = await run(p, shell);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(p.parse(r.stdout as String, r.stderr as String, r.exitCode).deleted, isTrue);
        expect(f('kelola').existsSync(), isFalse);
        expect(f('kelola-web').existsSync(), isTrue);
        expect(f('90-cloud-init-users').existsSync(), isTrue);
        expectOnlyTouched(['kelola']);
      });

      test('$shell: a visudo -c failure installs nothing', () async {
        if (!go(shell)) return;
        stubs(visudoOk: false);
        final before = f('kelola').readAsStringSync();
        final p = KelolaSudoRemoveProbe(
          path: kelolaSudoersPath,
          line: '$_p/usr/sbin/reboot ""',
        );
        final r = await run(p, shell);
        expect(r.exitCode, isNot(0));
        expect(r.stdout, isNot(contains(kelolaSudoRemoveOkMarker)));
        expect(f('kelola').readAsStringSync(), before);
        expect(
          () => p.parse(r.stdout as String, r.stderr as String, r.exitCode),
          throwsA(isA<KelolaException>()),
        );
        final calls = log.readAsLinesSync();
        expect(calls.where((c) => c.startsWith('install ')), isEmpty);
      });

      test('$shell: a line that is not there changes nothing', () async {
        if (!go(shell)) return;
        final before = f('kelola').readAsStringSync();
        final p = KelolaSudoRemoveProbe(
          path: kelolaSudoersPath,
          line: '$_p/usr/sbin/poweroff ""',
        );
        final r = await run(p, shell);
        expect(r.stdout, contains(kelolaSudoRemoveMissingMarker));
        expect(f('kelola').readAsStringSync(), before);
        expect(log.readAsLinesSync().where((c) => c.startsWith('install ')), isEmpty);
      });

      test('$shell: a symlink in place of the file is refused', () async {
        if (!go(shell)) return;
        f('kelola').deleteSync();
        Link('${d.path}/kelola').createSync('${d.path}/90-cloud-init-users');
        final p = KelolaSudoRemoveProbe(path: kelolaSudoersPath);
        final r = await run(p, shell);
        expect(r.stdout, contains(kelolaSudoRemoveLinkMarker));
        expect(Link('${d.path}/kelola').existsSync(), isTrue);
        expect(f('90-cloud-init-users').readAsStringSync(), 'root ALL=(ALL) ALL\n');
      });

      test('$shell: a wrong password changes nothing', () async {
        if (!go(shell)) return;
        final before = f('kelola').readAsStringSync();
        final proc = await Process.start('env', [
          'PATH=${shell == 'busybox' ? '${bin.path}:$bbDir' : '${bin.path}:/usr/bin:/bin'}',
          if (shell == 'busybox') ...['busybox', 'sh'] else 'dash',
          '-c',
          KelolaSudoRemoveProbe(path: kelolaSudoersPath).command(_facts),
        ]);
        proc.stdin.write('nope\n');
        await proc.stdin.close();
        await proc.stdout.drain<void>();
        expect(await proc.exitCode, isNot(0));
        expect(f('kelola').readAsStringSync(), before);
      });
    }
  });

  group('read script (real trees)', skip: Platform.isWindows, () {
    late Directory dir;
    late Directory d;
    late Directory bin;

    setUp(() {
      if (Platform.isWindows) return;
      dir = Directory.systemTemp.createTempSync('kelola_read');
      d = Directory('${dir.path}/sudoers.d')..createSync();
      bin = Directory('${dir.path}/bin')..createSync();
      // sudo -n refuses, as on a host without a matching rule.
      File('${bin.path}/sudo').writeAsStringSync(
        '#!/bin/sh\n'
        '[ "\$1" = -n ] || exit 9\n'
        'if [ "\$2" = -l ]; then\n'
        "  echo 'User hendr may run the following commands on h:'\n"
        "  echo '    (root) NOPASSWD: /usr/sbin/nginx -t'\n"
        '  exit 0\n'
        'fi\n'
        'echo "sudo: a password is required" >&2; exit 1\n',
      );
      Process.runSync('chmod', ['755', '${bin.path}/sudo']);
      File('${d.path}/kelola').writeAsStringSync('$_p/usr/sbin/reboot ""\n');
      File('${d.path}/kelola-web').writeAsStringSync('$_p/usr/sbin/nginx -t\n');
      Process.runSync('chmod', ['000', '${d.path}/kelola-web']);
    });

    tearDown(() {
      if (Platform.isWindows) return;
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
      dir.deleteSync(recursive: true);
    });

    for (final shell in const ['dash', 'busybox']) {
      test('$shell: readable, unreadable and absent files, plus the listing', () async {
        if (shell == 'dash' && !hasDash) {
          markTestSkipped('dash is not installed here');
          return;
        }
        if (shell == 'busybox' &&
            Process.runSync('sh', ['-c', 'command -v busybox']).exitCode != 0) {
          markTestSkipped('busybox is not installed here');
          return;
        }
        final isRoot =
            (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
        final p = KelolaSudoFilesProbe(sudoersDir: d.path);
        final r = Process.runSync('env', [
          'PATH=${bin.path}:/usr/bin:/bin',
          if (shell == 'busybox') ...['busybox', 'sh'] else 'dash',
          '-c',
          p.command(_facts),
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        final res = p.parse(r.stdout as String, r.stderr as String, r.exitCode);
        expect(res.files[0].state, KelolaSudoFileState.present);
        expect(res.files[0].lines, ['$_p/usr/sbin/reboot ""']);
        expect(res.files[1].state, KelolaSudoFileState.absent);
        expect(res.files[2].state, KelolaSudoFileState.present);
        // Root reads anything; everyone else needs the password.
        expect(res.files[2].lines, isRoot ? isNotNull : isNull);
        expect(res.listed, ['/usr/sbin/nginx -t']);
      });
    }
  });
}
