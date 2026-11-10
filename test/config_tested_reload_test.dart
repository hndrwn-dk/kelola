import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/config_tested_reload_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo_hint.dart';

const ubuntu = HostFacts(
  osId: 'ubuntu',
  osVersionId: '24.04',
  init: InitSystem.systemd,
  systemdVersion: 255,
  pkg: PackageManager.apt,
  fw: FirewallBackend.none,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

const alpine = HostFacts(
  osId: 'alpine',
  osVersionId: '3.20',
  init: InitSystem.openrc,
  systemdVersion: null,
  pkg: PackageManager.apk,
  fw: FirewallBackend.none,
  hasJournald: false,
  journalReadable: false,
  arch: 'x86_64',
);

const sysv = HostFacts(
  osId: 'debian',
  osVersionId: '12',
  init: InitSystem.sysvinit,
  systemdVersion: null,
  pkg: PackageManager.apt,
  fw: FirewallBackend.none,
  hasJournald: false,
  journalReadable: false,
  arch: 'x86_64',
);

const nginx = ConfigTestedReloadProbe(
  id: ServiceId.nginx,
  unit: 'nginx.service',
  testBin: '/usr/sbin/nginx',
);

const apache = ConfigTestedReloadProbe(
  id: ServiceId.apache,
  unit: 'apache2.service',
  testBin: '/usr/sbin/apache2ctl',
);

Matcher sudoHint(SudoHintKind kind, {String? unit, String? verb, String? target}) =>
    isA<SudoRequiredException>()
        .having((e) => e.context.kind, 'kind', kind)
        .having((e) => e.context.unit, 'unit', unit)
        .having((e) => e.context.verb, 'verb', verb)
        .having((e) => e.context.target, 'target', target);

void main() {
  test('risk == mutate', () {
    expect(nginx.risk, RiskLevel.mutate);
    expect(apache.risk, RiskLevel.mutate);
    expect(nginx.needsSudo, isTrue);
    expect(nginx.auditTitle, 'Reloaded nginx (config tested)');
    expect(apache.auditTitle, 'Reloaded Apache (config tested)');
  });

  test('systemd command runs -t before systemctl reload and exits 3 on failure',
      () {
    final cmd = nginx.command(ubuntu);
    final test = cmd.indexOf("sudo -n '/usr/sbin/nginx' -t");
    final guard = cmd.indexOf(r'[ "$rc" = 0 ] || exit 3');
    final reload = cmd.indexOf("sudo -n systemctl reload 'nginx.service'");
    final verify = cmd.indexOf(
      "systemctl show 'nginx.service' -p ActiveState -p SubState --no-pager",
    );
    expect(test, greaterThanOrEqualTo(0));
    expect(guard, greaterThan(test));
    expect(reload, greaterThan(guard));
    expect(verify, greaterThan(reload));
    for (final m in ['---TEST---', '---RELOAD---', '---VERIFY---']) {
      expect(cmd, contains('echo $m'));
    }
    // Every sudo call is sudo -n with stdin from /dev/null.
    final calls = cmd.replaceAll('command -v sudo ', '');
    expect(RegExp(r'sudo (?!-n )').hasMatch(calls), isFalse);
    for (final line in cmd.split('\n')) {
      if (line.contains('sudo -n ')) {
        expect(line, contains('</dev/null'), reason: line);
      }
    }
    expect(cmd, isNot(contains('sudo -S')));
    expect(cmd, isNot(contains('rc-service')));
    final a = apache.command(ubuntu);
    expect(a, contains("sudo -n '/usr/sbin/apache2ctl' -t"));
    expect(a, contains("sudo -n systemctl reload 'apache2.service'"));
  });

  test('openrc command uses rc-service <svc> reload', () {
    const probe = ConfigTestedReloadProbe(
      id: ServiceId.nginx,
      unit: 'nginx',
      testBin: '/usr/sbin/nginx',
    );
    final cmd = probe.command(alpine);
    expect(cmd, contains("sudo -n '/usr/sbin/nginx' -t"));
    expect(cmd, contains("sudo -n rc-service 'nginx' reload"));
    expect(cmd, contains("rc-service 'nginx' status"));
    expect(cmd, isNot(contains('systemctl')));
    expect(
      cmd.indexOf(r'[ "$rc" = 0 ] || exit 3'),
      lessThan(cmd.indexOf("rc-service 'nginx' reload")),
    );
  });

  test('unknown init refuses: nothing run', () {
    final cmd = nginx.command(sysv);
    expect(cmd, isNot(contains('sudo')));
    expect(cmd, isNot(contains('nginx -t')));
    expect(cmd, contains('@refused='));
    final r = nginx.parse('@refused=init\n', '', 2);
    expect(r.outcome, ReloadOutcome.failed);
  });

  test('host-derived unit and testBin are validated; unsafe → no sudo call',
      () {
    for (final p in [
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: "nginx.service; reboot",
        testBin: '/usr/sbin/nginx',
      ),
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: "/usr/sbin/nginx';reboot;'",
      ),
      // Safe path, wrong binary.
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '/bin/sh',
      ),
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: 'nginx',
      ),
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '/usr/../bin/nginx',
      ),
      const ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: '',
        testBin: '/usr/sbin/nginx',
      ),
      // nginx is not an Apache config tester.
      const ConfigTestedReloadProbe(
        id: ServiceId.apache,
        unit: 'apache2.service',
        testBin: '/usr/sbin/nginx',
      ),
    ]) {
      final cmd = p.command(ubuntu);
      expect(cmd, isNot(contains('sudo')), reason: cmd);
      expect(cmd, isNot(contains('reboot')), reason: cmd);
      expect(cmd, isNot(contains('/bin/sh')), reason: cmd);
      expect(cmd, contains('@refused=unsafe'));
      expect(cmd, contains('exit 2'));
      expect(p.parse('@refused=unsafe\n', '', 2).outcome, ReloadOutcome.failed);
    }
    expect(
      isSafeReloadTarget(id: ServiceId.nginx, unit: 'nginx.service', testBin: '/usr/sbin/nginx'),
      isTrue,
    );
    expect(
      isSafeReloadTarget(id: ServiceId.apache, unit: 'httpd.service', testBin: '/usr/sbin/apachectl'),
      isTrue,
    );
  });

  group('parse', () {
    test('exit 3 → testFailed with test output', () {
      const out = '@init=systemd\n'
          '---TEST---\n'
          '|nginx: [emerg] unknown directive "servr" in /etc/nginx/conf.d/a.conf:3\n'
          '|nginx: configuration file /etc/nginx/nginx.conf test failed\n'
          '@rc=1\n';
      final r = nginx.parse(out, '', 3);
      expect(r.outcome, ReloadOutcome.testFailed);
      expect(
        r.testOutput,
        'nginx: [emerg] unknown directive "servr" in /etc/nginx/conf.d/a.conf:3\n'
        'nginx: configuration file /etc/nginx/nginx.conf test failed',
      );
      expect(r.activeState, isNull);
    });

    test('sudo password prompt → SudoRequiredException(webServices)', () {
      const out = '@init=systemd\n---TEST---\n@rc=nosudo\n';
      expect(
        () => nginx.parse(out, '', 4),
        throwsA(sudoHint(SudoHintKind.webServices, target: 'nginx')),
      );
      expect(
        () => apache.parse(out, '', 4),
        throwsA(sudoHint(SudoHintKind.webServices, target: 'apache')),
      );
      // Cut output with a prompt on stderr reads the same.
      expect(
        () => nginx.parse('', 'sudo: a password is required\n', 1),
        throwsA(sudoHint(SudoHintKind.webServices, target: 'nginx')),
      );
    });

    test('a test failure mentioning sudo is still testFailed', () {
      const out = '@init=systemd\n---TEST---\n'
          '|nginx: [emerg] open() "/etc/nginx/sudo password" failed\n'
          '@rc=1\n';
      expect(nginx.parse(out, 'a password is required', 3).outcome,
          ReloadOutcome.testFailed);
    });

    test('an OpenRC reload refusal carries the rc-service marker', () {
      const rc = '@init=openrc\n---TEST---\n@rc=0\n'
          '---RELOAD---\n@rc=nosudo\n---VERIFY---\n| * status: started\n';
      const openrcProbe = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx',
        testBin: '/usr/sbin/nginx',
      );
      expect(
        () => openrcProbe.parse(rc, '', 1),
        throwsA(
          isA<SudoRequiredException>()
              .having((e) => e.context.kind, 'kind', SudoHintKind.webServices)
              .having((e) => e.context.binary, 'binary', webOpenRcReloadBinary),
        ),
      );
      // A refused config test is a read the lens grant covers: no marker.
      const test = '@init=openrc\n---TEST---\n@rc=nosudo\n';
      expect(
        () => openrcProbe.parse(test, '', 4),
        throwsA(
          isA<SudoRequiredException>()
              .having((e) => e.context.kind, 'kind', SudoHintKind.webServices)
              .having((e) => e.context.binary, 'binary', isNull),
        ),
      );
    });

    test('reload leg sudo refusal: systemd hint on systemd, webServices on openrc',
        () {
      const sd = '@init=systemd\n---TEST---\n|nginx: test is successful\n@rc=0\n'
          '---RELOAD---\n@rc=nosudo\n---VERIFY---\n|ActiveState=active\n';
      expect(
        () => nginx.parse(sd, '', 1),
        throwsA(
          sudoHint(SudoHintKind.systemd, unit: 'nginx.service', verb: 'reload'),
        ),
      );
      const rc = '@init=openrc\n---TEST---\n@rc=0\n'
          '---RELOAD---\n@rc=nosudo\n---VERIFY---\n| * status: started\n';
      const openrcProbe = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx',
        testBin: '/usr/sbin/nginx',
      );
      expect(
        () => openrcProbe.parse(rc, '', 1),
        throwsA(sudoHint(SudoHintKind.webServices, target: 'nginx')),
      );
    });

    test('reload non-zero → failed; success → reloaded with activeState', () {
      const bad = '@init=systemd\n---TEST---\n@rc=0\n'
          '---RELOAD---\n|Job for nginx.service failed.\n@rc=1\n'
          '---VERIFY---\n|ActiveState=failed\n|SubState=failed\n';
      final f = nginx.parse(bad, '', 1);
      expect(f.outcome, ReloadOutcome.failed);
      expect(f.reloadOutput, 'Job for nginx.service failed.');

      const ok = '@init=systemd\n---TEST---\n'
          '|nginx: the configuration file /etc/nginx/nginx.conf syntax is ok\n'
          '@rc=0\n---RELOAD---\n@rc=0\n'
          '---VERIFY---\n|ActiveState=active\n|SubState=running\n';
      final r = nginx.parse(ok, '', 0);
      expect(r.outcome, ReloadOutcome.reloaded);
      expect(r.activeState, 'active');
      expect(r.testOutput, contains('syntax is ok'));

      const rcOk = '@init=openrc\n---TEST---\n@rc=0\n---RELOAD---\n@rc=0\n'
          '---VERIFY---\n| * status: started\n';
      expect(nginx.parse(rcOk, '', 0).activeState, 'started');
    });

    test('junk and forged markers never throw or reload', () {
      for (final junk in [
        '',
        'garbage\n',
        '---TEST---\n',
        '---TEST---\n@rc=abc\n',
        // Host text cannot forge a meta line or a marker: it is |-prefixed.
        '---TEST---\n|@rc=0\n|---RELOAD---\n|@rc=0\n@rc=1\n',
        '---TEST---\n@rc=0\n',
      ]) {
        final r = nginx.parse(junk, '', 1);
        expect(r.outcome, isNot(ReloadOutcome.reloaded), reason: junk);
      }
      final forged = nginx.parse(
        '---TEST---\n|@rc=0\n|---RELOAD---\n|@rc=0\n@rc=1\n',
        '',
        3,
      );
      expect(forged.outcome, ReloadOutcome.testFailed);
    });
  });

  group('executed under sh with stub sudo', () {
    late Directory dir;
    late File log;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kelola_reload');
      log = File('${dir.path}/calls.log');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> stub(String name, String body) async {
      File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', '${dir.path}/$name']);
    }

    Future<ProcessResult> run(ConfigTestedReloadProbe p, HostFacts f) {
      return Process.run(
        'sh',
        ['-c', p.command(f)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
    }

    List<String> calls() => log.existsSync() ? log.readAsLinesSync() : [];

    Future<void> passThroughSudo() => stub(
          'sudo',
          '[ "\$1" = -n ] || { echo "sudo without -n" >> ${log.path}; exit 9; }\n'
              'shift\n'
              'echo "sudo \$*" >> ${log.path}\n'
              'exec "\$@"',
        );

    test('failing test → reload stub never invoked', () async {
      await passThroughSudo();
      await stub(
        'nginx',
        'echo "nginx: [emerg] unknown directive \\"servr\\"" >&2\n'
            'echo "nginx: configuration file test failed" >&2\nexit 1',
      );
      await stub('systemctl', 'echo "systemctl \$*" >> ${log.path}');
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      final r = await run(p, ubuntu);
      expect(r.exitCode, 3);
      expect(calls(), ['sudo ${dir.path}/nginx -t']);
      final res = p.parse(r.stdout as String, r.stderr as String, r.exitCode);
      expect(res.outcome, ReloadOutcome.testFailed);
      expect(res.testOutput, contains('unknown directive "servr"'));
      expect(res.testOutput, contains('test failed'));
    }, skip: Platform.isWindows);

    test('passing test → reload then verify → reloaded', () async {
      await passThroughSudo();
      await stub('nginx', 'echo "nginx: test is successful" >&2');
      await stub(
        'systemctl',
        'echo "systemctl \$*" >> ${log.path}\n'
            'if [ "\$1" = show ]; then echo ActiveState=active; echo SubState=running; fi',
      );
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      final r = await run(p, ubuntu);
      expect(calls(), [
        'sudo ${dir.path}/nginx -t',
        'sudo systemctl reload nginx.service',
        'systemctl reload nginx.service',
        'systemctl show nginx.service -p ActiveState -p SubState --no-pager',
      ]);
      final res = p.parse(r.stdout as String, r.stderr as String, r.exitCode);
      expect(res.outcome, ReloadOutcome.reloaded);
      expect(res.activeState, 'active');
      expect(r.exitCode, 0);
    }, skip: Platform.isWindows);

    test('sudo password prompt on the test leg → webServices, nothing run',
        () async {
      await stub(
        'sudo',
        'echo "sudo \$*" >> ${log.path}\n'
            'echo "sudo: a password is required" >&2\nexit 1',
      );
      await stub('nginx', 'echo "nginx \$*" >> ${log.path}');
      await stub('systemctl', 'echo "systemctl \$*" >> ${log.path}');
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      final r = await run(p, ubuntu);
      expect(calls(), ['sudo -n ${dir.path}/nginx -t']);
      expect(
        () => p.parse(r.stdout as String, r.stderr as String, r.exitCode),
        throwsA(sudoHint(SudoHintKind.webServices, target: 'nginx')),
      );
    }, skip: Platform.isWindows);

    test('sudo refused on the reload leg → systemd hint for the unit', () async {
      await stub(
        'sudo',
        'shift\n'
            'if [ "\$1" = systemctl ]; then echo "sudo: a password is required" >&2; exit 1; fi\n'
            'exec "\$@"',
      );
      await stub('nginx', 'echo "nginx: test is successful" >&2');
      await stub(
        'systemctl',
        'if [ "\$1" = show ]; then echo ActiveState=active; fi',
      );
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      final r = await run(p, ubuntu);
      expect(
        () => p.parse(r.stdout as String, r.stderr as String, r.exitCode),
        throwsA(
          sudoHint(SudoHintKind.systemd, unit: 'nginx.service', verb: 'reload'),
        ),
      );
    }, skip: Platform.isWindows);

    test('a config error that mentions sudo is testFailed, not sudo-required',
        () async {
      await passThroughSudo();
      await stub('systemctl', 'echo "systemctl \$*" >> ${log.path}');
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      await stub(
        'nginx',
        'echo "nginx: [emerg] open() \\"/etc/sudo: a password is required\\" failed" >&2\n'
            'exit 1',
      );
      final r2 = await run(p, ubuntu);
      expect(r2.exitCode, 3);
      expect(calls(), ['sudo ${dir.path}/nginx -t']);
      final res =
          p.parse(r2.stdout as String, r2.stderr as String, r2.exitCode);
      expect(res.outcome, ReloadOutcome.testFailed);
      expect(res.testOutput, contains('/etc/sudo: a password is required'));
    }, skip: Platform.isWindows);

    test('sudo refusals in classic and sudo-rs wording are detected', () async {
      for (final msg in [
        'sudo: a password is required',
        'sudo: a terminal is required to read the password; either use the -S option',
        'sudo: interactive authentication is required',
        "sudo: I'm sorry deploy. I'm afraid I can't do that",
        'Sorry, user deploy is not allowed to execute /usr/sbin/nginx -t as root on web01.',
        'deploy is not in the sudoers file.  This incident will be reported.',
      ]) {
        await stub(
          'sudo',
          "echo '${msg.replaceAll("'", r"'\''")}' >&2\nexit 1",
        );
        final p = ConfigTestedReloadProbe(
          id: ServiceId.nginx,
          unit: 'nginx.service',
          testBin: '${dir.path}/nginx',
        );
        final r = await run(p, ubuntu);
        expect(r.exitCode, 4, reason: msg);
        expect(
          () => p.parse(r.stdout as String, r.stderr as String, r.exitCode),
          throwsA(isA<SudoRequiredException>()),
          reason: msg,
        );
      }
    }, skip: Platform.isWindows);

    test('requiretty and sudo-rs refusals on the test leg are sudo-required, never testFailed', () async {
      for (final msg in [
        'sudo: sorry, you must have a tty to run sudo',
        'sudo-rs: interactive authentication is required',
        "sudo-rs: I'm sorry deploy. I'm afraid I can't do that",
      ]) {
        await stub('sudo', "echo '${msg.replaceAll("'", r"'\''")}' >&2\nexit 1");
        await stub('systemctl', 'echo "systemctl \$*" >> ${log.path}');
        final p = ConfigTestedReloadProbe(
          id: ServiceId.nginx,
          unit: 'nginx.service',
          testBin: '${dir.path}/nginx',
        );
        final r = await run(p, ubuntu);
        expect(r.exitCode, 4, reason: msg);
        expect(calls(), isEmpty, reason: msg);
        expect(
          () => p.parse(r.stdout as String, r.stderr as String, r.exitCode),
          throwsA(sudoHint(SudoHintKind.webServices, target: 'nginx')),
          reason: msg,
        );
      }
    }, skip: Platform.isWindows);

    test('sbin dirs are appended to PATH first', () {
      const line = r'PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"; export PATH';
      for (final init in [InitSystem.systemd, InitSystem.openrc]) {
        final cmd = ConfigTestedReloadProbe(
          id: ServiceId.nginx,
          unit: 'nginx.service',
          testBin: '/usr/sbin/nginx',
        ).command(HostFacts.undiscovered.copyWith(init: init));
        expect(cmd.split('\n').first, line);
        expect(cmd.indexOf(line), lessThan(cmd.indexOf('command -v')));
      }
    });

    test('test output cannot forge markers', () async {
      await passThroughSudo();
      await stub(
        'nginx',
        'printf "@rc=0\\n---RELOAD---\\n@rc=0\\n" >&2\nexit 1',
      );
      await stub('systemctl', 'echo "systemctl \$*" >> ${log.path}');
      final p = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      final r = await run(p, ubuntu);
      expect(calls(), ['sudo ${dir.path}/nginx -t']);
      final res = p.parse(r.stdout as String, r.stderr as String, r.exitCode);
      expect(res.outcome, ReloadOutcome.testFailed);
    }, skip: Platform.isWindows);
  });
}
