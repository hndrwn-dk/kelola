import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/service_detect_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/container_services.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detect_parser.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/domain/services/web_lens_parser.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/presentation/screens/web_lens_screen.dart';
import 'package:kelola/presentation/services/stack_section.dart';
import 'package:kelola/presentation/widgets/enable_kelola_sudo_flow.dart';

final _now = DateTime.utc(2026, 11, 14, 12);

const _ubuntu = HostFacts(
  osId: 'ubuntu',
  osVersionId: '26.04',
  init: InitSystem.systemd,
  systemdVersion: 257,
  pkg: PackageManager.apt,
  fw: FirewallBackend.ufw,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
  runtimes: ['docker'],
);

/// `docker ps -a --no-trunc --format '{{json .}}'` from east-worker-uat,
/// trimmed to the fields the parser reads, as the probe prints it.
const _lampPs = '''
---CONTAINERS---
|{"Command":"\\"docker-entrypoint.sh apache2-foreground\\"","Image":"phpmyadmin:5","Names":"lamp-pma","State":"running"}
|{"Command":"\\"docker-php-entrypoint apache2-foreground\\"","Image":"lamp-web","Names":"lamp-web","State":"running"}
|{"Command":"\\"docker-entrypoint.sh mariadbd\\"","Image":"mariadb:11.4","Names":"lamp-db","State":"running"}
|{"Command":"\\"redis-server\\"","Image":"redis:7","Names":"infra-cache-1","State":"exited"}
''';

DetectedService _apache(String name) => DetectedService(
  id: ServiceId.apache,
  state: ServiceState.running,
  container: name,
);

void main() {
  group('detection', () {
    test('the lamp compose stack: two Apache containers and MariaDB', () {
      final d = parseServiceDetection(_lampPs, now: _now);
      expect(
        [for (final s in d.services) '${s.id.name}:${s.container}'],
        ['apache:lamp-pma', 'apache:lamp-web', 'mariadb:lamp-db'],
      );
      final db = d.services.last;
      expect(db.version, '11.4');
      expect(db.state, ServiceState.running);
      expect(db.unit, isNull);
      expect(db.binaries, isEmpty);
      expect(d.services.first.version, isNull, reason: 'tag 5 is phpMyAdmin');
    });

    test('host services come first, then containers', () {
      final d = parseServiceDetection(
        '---UNITS---\nnginx.service failed failed\n---BIN---\n'
        'nginx /usr/sbin/nginx\n$_lampPs',
        now: _now,
      );
      expect(d.services.first.id, ServiceId.nginx);
      expect(d.services.first.inContainer, isFalse);
      expect(d.services.where((s) => s.inContainer), hasLength(3));
    });

    test('image and command rules', () {
      ServiceId? id(String image, [String cmd = '']) =>
          serviceIdForContainer(image: image, command: cmd);
      expect(id('nginx:1.27-alpine'), ServiceId.nginx);
      expect(
        id('docker.io/nginxinc/nginx-unprivileged:stable'),
        ServiceId.nginx,
      );
      expect(id('myshop', '"nginx -g \'daemon off;\'"'), ServiceId.nginx);
      expect(id('httpd:2.4.62'), ServiceId.apache);
      expect(id('php:8.3-apache'), ServiceId.apache);
      expect(id('php:8.3-fpm'), isNull);
      expect(
        id('ghcr.io/x/y@sha256:abc', 'httpd-foreground'),
        ServiceId.apache,
      );
      expect(id('mariadb:11.4'), ServiceId.mariadb);
      expect(id('mysql:8.4'), ServiceId.mysql);
      expect(id('postgres:17'), ServiceId.postgres);
      expect(id('app', 'postgres -c shared_buffers=1GB'), ServiceId.postgres);
      expect(id('app', 'python manage.py runserver'), isNull);
      expect(versionFromTag(splitImage('httpd:2.4.62').tag), '2.4.62');
      expect(versionFromTag(splitImage('php:8.3-apache').tag), isNull);
      expect(versionFromTag(splitImage('nginx').tag), isNull);
    });

    test('state mapping', () {
      expect(containerServiceState('running'), ServiceState.running);
      expect(containerServiceState('restarting'), ServiceState.failed);
      for (final s in [
        'exited',
        'created',
        'paused',
        'dead',
        'removing',
        '?',
      ]) {
        expect(containerServiceState(s), ServiceState.stopped, reason: s);
      }
    });

    test('junk, unsafe names, duplicates and denied are skipped', () {
      final d = parseServiceDetection(
        '---CONTAINERS---\n'
        '@docker=denied\n'
        '|not json\n'
        '|["array"]\n'
        '{"Image":"nginx","Names":"unprefixed","State":"running"}\n'
        '|{"Image":"nginx","Names":"a;rm -rf /","State":"running"}\n'
        '|{"Image":"nginx","Names":"-dash","State":"running"}\n'
        '|{"Image":"nginx","Names":"${'x' * 129}","State":"running"}\n'
        '|{"Image":"nginx","Names":"web","State":"running"}\n'
        '|{"Image":"httpd","Names":"web","State":"running"}\n'
        '|{"Image":"","Names":"empty","State":"running"}\n',
        now: _now,
      );
      expect([for (final s in d.services) s.container], ['web']);
      expect(d.services.single.id, ServiceId.nginx);
    });

    test('container text cannot end the section early', () {
      // The probe breaks up `---`; even unbroken, a fake marker only ends
      // this last section, never forges an earlier one.
      final d = parseServiceDetection(
        '---UNITS---\n---CONTAINERS---\n'
        '|{"Command":"echo -- -UNITS-- -","Image":"nginx","Names":"a","State":"running"}\n'
        '|{"Image":"httpd","Names":"b","State":"running"}\n',
        now: _now,
      );
      expect([for (final s in d.services) s.container], ['a', 'b']);
    });

    test('JSON round trip; an unsafe cached name drops the entry', () {
      final s = _apache('lamp-web');
      final back = DetectedService.fromJson(s.toJson())!;
      expect(back.container, 'lamp-web');
      expect(back.inContainer, isTrue);
      expect(
        DetectedService.fromJson({
          'id': 'apache',
          'state': 'running',
          'ctr': "x'; reboot; '",
        }),
        isNull,
      );
      expect(
        DetectedService.fromJson({
          'id': 'apache',
          'state': 'running',
          'ctr': 7,
        }),
        isNull,
      );
    });

    test('probe prints the containers section last, every line prefixed', () {
      final cmd = const ServiceDetectProbe().command(_ubuntu);
      final i = cmd.indexOf('echo ---CONTAINERS---');
      expect(i, greaterThan(cmd.indexOf('echo ---PORTS---')));
      expect(cmd.substring(i), contains(r"sed 's/---/-- -/g; s/^/|/'"));
    });

    test('sudo for docker only when asked (pull-to-refresh)', () {
      final auto = const ServiceDetectProbe().command(_ubuntu);
      expect(auto, isNot(contains('sudo')));
      expect(auto, contains('@docker=skipped'));
      final pull = const ServiceDetectProbe(dockerSudo: true).command(_ubuntu);
      expect(
        pull,
        contains("sudo -n docker ps -a --no-trunc --format '{{json .}}'"),
      );
      expect(pull, contains('@docker=denied'));
    });

    test('a skipped container read keeps the last container list', () {
      final before = parseServiceDetection(_lampPs, now: _now);
      final skipped = parseServiceDetection(
        '---UNITS---\nnginx.service failed failed\n'
        '---CONTAINERS---\n@docker=skipped\n',
        now: _now,
      );
      expect(skipped.containersSkipped, isTrue);
      final merged = skipped.keepingContainersOf(before);
      expect(merged.services.where((s) => s.inContainer), hasLength(3));
      expect(merged.services.first.id, ServiceId.nginx);

      // Denied after sudo, or no docker: the list is what was read.
      final denied = parseServiceDetection(
        '---CONTAINERS---\n@docker=denied\n',
        now: _now,
      );
      expect(denied.containersSkipped, isFalse);
      expect(denied.keepingContainersOf(before).services, isEmpty);
    });
  });

  group('STACK tile and lens title', () {
    test('a container names itself instead of a version', () {
      expect(stackTileMeta(_apache('lamp-web')), 'lamp-web · running');
      expect(webLensTitle(_apache('lamp-web')), 'Apache httpd · lamp-web');
      const host = DetectedService(
        id: ServiceId.nginx,
        state: ServiceState.failed,
        version: '1.28.3',
      );
      expect(stackTileMeta(host), '1.28.3 · failed');
      expect(webLensTitle(host), 'nginx 1.28.3');
    });
  });

  group('lens probe script', () {
    WebLensProbe probe(String name, [ServiceId id = ServiceId.apache]) =>
        WebLensProbe(id: id, binaries: const {}, container: name);

    test('the container name is the only host value, single-quoted', () {
      final cmd = probe('lamp-web').command(_ubuntu);
      expect(cmd, contains("C='lamp-web'"));
      expect(probe('lamp-web').auditTitle, 'Read Apache (lamp-web)');
    });

    test('an unsafe name never reaches the script', () {
      final cmd = probe("x'; reboot; '").command(_ubuntu);
      expect(cmd, isNot(contains('reboot')));
      expect(cmd, contains('@docker=denied'));
      expect(cmd, isNot(contains('C=')));
    });

    test('docker exec only without sudo, on a running container', () {
      for (final id in [ServiceId.apache, ServiceId.nginx]) {
        final cmd = probe('web', id).command(_ubuntu);
        expect(cmd, isNot(contains('sudo -n docker exec')));
        expect(cmd, isNot(contains('dk exec')));
        expect(
          cmd,
          contains(r'x=no; [ "$D" = plain ] && [ "$s" = running ] && x=yes'),
        );
        // Every exec sits after the gate.
        final gate = cmd.indexOf('x=yes');
        for (final m in RegExp('docker exec').allMatches(cmd)) {
          expect(m.start, greaterThan(gate));
        }
        expect(cmd, contains(r'dk logs --tail 60 "$C"'));
        expect(cmd, contains(r'dk logs --tail 2000 "$C"'));
      }
    });

    test('the in-container script is constant', () {
      expect(
        containerWebScript(ServiceId.apache, '-S'),
        r'for b in apachectl apache2ctl httpd; do if command -v "$b" '
        r'>/dev/null 2>&1; then exec "$b" -S; fi; done; echo kelola-nobin; '
        'exit 127',
      );
    });
  });

  group('lens parser on container output', () {
    WebLens parse(String out, [ServiceId id = ServiceId.apache]) =>
        parseWebLens(out, id: id, now: _now);

    test('running container, config ok, logs read', () {
      final l = parse('''
---ACTIVE---
@docker=plain
|running
---CONFTEST---
|Syntax OK
@rc=0
---DUMP---
|VirtualHost configuration:
|*:80                   172.18.0.3 (/etc/apache2/sites-enabled/000-default.conf:1)
---CERTS---
@done=1
---ERRLOG---
@read=ok
|[mpm_prefork:notice] AH00163: Apache/2.4.65 configured
---ACCESS---
@read=ok
|    120 200
|      3 404
''');
      expect(l.activeState, 'running');
      expect(l.configOk, isTrue);
      expect(l.sectionErrors, isEmpty);
      expect(l.statusCounts, {200: 120, 404: 3});
      expect(l.errorLogTail, hasLength(1));
      expect(l.findings.where((f) => f.level != WebFindingLevel.fact), isEmpty);
    });

    test('restarting or exited is a failed finding; config not read', () {
      for (final state in ['restarting', 'exited']) {
        final l = parse('''
---ACTIVE---
@docker=plain
|$state
---CONFTEST---
@rc=notrunning
---DUMP---
---CERTS---
---ERRLOG---
@read=ok
---ACCESS---
@read=ok
''');
        expect(l.findings.first.kind, WebFindingKind.serviceNotActive);
        expect(l.findings.first.subject, state);
        expect(
          l.sectionErrors[WebLensSection.configTest],
          'Container is not running; config not read',
        );
        expect(
          l.sectionErrors[WebLensSection.dump],
          'Container is not running; config not read',
        );
      }
    });

    test('docker through sudo: state and logs, config explains the group', () {
      final l = parse('''
---ACTIVE---
@docker=sudo
|running
---CONFTEST---
@rc=needsgroup
---DUMP---
---CERTS---
---ERRLOG---
@read=ok
|AH00558: apache2: Could not reliably determine the server's name
---ACCESS---
@read=ok
''');
      expect(l.activeState, 'running');
      expect(l.sectionErrors[WebLensSection.configTest], webDockerNeedsGroup);
      expect(l.sectionErrors[WebLensSection.certs], webDockerNeedsGroup);
      expect(l.sectionErrors.containsKey(WebLensSection.errorLog), isFalse);
    });

    test('no docker access: every section says so, never a web sudo hint', () {
      final l = parse('''
---ACTIVE---
@docker=denied
---CONFTEST---
@rc=nodocker
---DUMP---
---CERTS---
---ERRLOG---
@read=fail
---ACCESS---
@read=fail
''');
      for (final s in WebLensSection.values) {
        expect(l.sectionErrors[s], webDockerDenied, reason: s.name);
      }
    });

    test('a sudo-looking rc in a container is not the kelola-web hint', () {
      expect(
        () => parse(
          '---ACTIVE---\n@docker=plain\n|running\n'
          '---CONFTEST---\n@rc=nosudo\n---DUMP---\n',
        ),
        returnsNormally,
      );
    });
  });

  group('Containers sudo group', () {
    const regex = ClassicSudo(1, 9, 15);
    const noRegex = ClassicSudo(1, 9, 5);

    KelolaSudoersSpec spec(SudoFlavor sudo) => buildKelolaSudoersSpec(
      user: 'hendr',
      facts: _ubuntu,
      groups: const {KelolaSudoersGroup.containers},
      sudo: sudo,
    );

    test('default only when the host has docker', () {
      expect(
        defaultKelolaSudoersGroups(_ubuntu, sudo: regex),
        contains(KelolaSudoersGroup.containers),
      );
      expect(
        defaultKelolaSudoersGroups(
          _ubuntu.copyWith(runtimes: const ['podman']),
          sudo: regex,
        ),
        isNot(contains(KelolaSudoersGroup.containers)),
      );
      expect(
        kelolaSudoersGroupLabel(KelolaSudoersGroup.containers),
        'Containers',
      );
    });

    test('exact rules everywhere, name rules only with regex', () {
      expect(spec(noRegex).commands, [
        '/usr/bin/docker info',
        '/usr/bin/docker ps -a --format {{json .}}',
        '/usr/bin/docker ps -a --no-trunc --format {{json .}}',
      ]);
      expect(spec(regex).commands, hasLength(4));
      // inspect shows container env (credentials): never through sudo.
      expect(spec(regex).commands.join('\n'), isNot(contains('inspect')));
    });

    test('no rule can exec, run, copy or change anything', () {
      for (final rule in spec(regex).commands) {
        for (final bad in [
          'exec',
          'run',
          'cp',
          'start',
          'stop',
          'restart',
          'rm',
          'kill',
          'compose',
          'build',
          'pull',
          'update',
          'commit',
          'ALL',
          '*.*',
        ]) {
          expect(rule.split(' '), isNot(contains(bad)), reason: rule);
        }
      }
    });

    test('allows exactly the argv the probes send', () {
      bool allows(String args) {
        for (final rule in spec(regex).commands) {
          final ruleArgs = rule.substring('/usr/bin/docker '.length);
          if (ruleArgs.startsWith('^')
              ? RegExp(ruleArgs).hasMatch(args)
              : ruleArgs == args) {
            return true;
          }
        }
        return false;
      }

      for (final ok in [
        'info',
        'ps -a --format {{json .}}',
        'ps -a --no-trunc --format {{json .}}',
        'logs --tail 60 lamp-web',
        'logs --tail 2000 infra-cache-1',
      ]) {
        expect(allows(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'exec lamp-web sh',
        'inspect --type container lamp-web',
        'inspect lamp-web',
        'inspect --type container lamp-web other',
        'inspect --type container -f {{.Config.Env}} lamp-web',
        'logs --tail 61 lamp-web',
        'logs --tail 60 --follow lamp-web',
        'logs --tail 60 -lamp-web',
        'ps -a',
      ]) {
        expect(allows(bad), isFalse, reason: bad);
      }

      // The sudo fallbacks in the scripts are those exact argv.
      expect(
        const ContainerListProbe().command(_ubuntu),
        contains("sudo -n docker ps -a --format '{{json .}}'"),
      );
      expect(
        const ContainerListProbe().command(_ubuntu),
        contains('sudo -n docker info'),
      );
      final lens = WebLensProbe(
        id: ServiceId.apache,
        binaries: const {},
        container: 'lamp-web',
      ).command(_ubuntu);
      expect(
        lens,
        contains("sudo -n docker ps -a --no-trunc --format '{{json .}}'"),
      );
      expect(lens, isNot(contains('inspect')));
    });

    test('real visudo accepts the group', () {
      const visudo = '/usr/sbin/visudo';
      if (!File(visudo).existsSync()) {
        expect(Platform.environment['CI'] == 'true', isFalse);
        markTestSkipped('visudo is not installed here');
        return;
      }
      final dir = Directory.systemTemp.createTempSync('kelola_docker_sudo');
      addTearDown(() => dir.deleteSync(recursive: true));
      for (final sudo in [regex, noRegex]) {
        final file = File('${dir.path}/kelola-${sudo.patch}')
          ..writeAsStringSync(spec(sudo).content);
        final r = Process.runSync(visudo, ['-c', '-f', file.path]);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
    });
  });

  group('the script against a fake docker', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('kelola_m52c'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> stub(String name, String body) async {
      File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', '${dir.path}/$name']);
    }

    /// Docker reachable plain (`plain`), only through sudo (`sudo`) or not
    /// at all (`none`). The container's config test binary is a stub too.
    Future<WebLens> run({
      required String access,
      String status = 'running',
    }) async {
      await stub('docker', '''
[ "$access" = none ] && exit 1
[ "$access" = sudo ] && [ -z "\$VIA_SUDO" ] && exit 1
case "\$1" in
  ps) echo '{"Labels":"x=\\\\"Names\\\\":\\\\"lamp-web\\\\",\\\\"State\\\\":\\\\"exited\\\\"","Names":"lamp-web-2","State":"exited"}'
      echo '{"Command":"docker-php-entrypoint apache2-foreground","Names":"lamp-web","State":"$status","Status":"Up 5 minutes"}' ;;
  exec) shift 2; exec "\$@" ;;
  logs) echo '10.0.0.9 - - [14/Nov/2026:19:00:00 +0000] "GET / HTTP/1.1" 200 45'
        echo '10.0.0.9 - - [14/Nov/2026:19:00:01 +0000] "GET /x HTTP/1.1" 404 9'
        echo 'AH00094: Command line: apache2 -D FOREGROUND' >&2 ;;
  *) exit 1 ;;
esac''');
      await stub('sudo', '[ "\$1" = -n ] && shift; VIA_SUDO=1 exec "\$@"');
      await stub('apachectl', '''
case "\$1" in
  -t) echo 'Syntax OK' >&2 ;;
  -S) echo 'VirtualHost configuration:'
      echo '*:80                   lamp.local (/etc/apache2/sites-enabled/000-default.conf:1)' ;;
esac''');
      final probe = WebLensProbe(
        id: ServiceId.apache,
        binaries: const {},
        container: 'lamp-web',
      );
      final r = await Process.run(
        'sh',
        ['-c', probe.command(_ubuntu)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      return probe.parse(r.stdout as String, r.stderr as String, r.exitCode);
    }

    final skip = Platform.isWindows ? 'needs a POSIX sh and chmod' : null;

    test('plain docker: state, config test, vhosts and both logs', () async {
      final l = await run(access: 'plain');
      expect(l.activeState, 'running');
      expect(l.configOk, isTrue);
      expect(l.vhosts.single.serverNames, ['lamp.local']);
      expect(l.statusCounts, {200: 1, 404: 1});
      expect(l.errorLogTail.single, contains('AH00094'));
      expect(l.sectionErrors, isEmpty);
    }, skip: skip);

    test('docker through sudo only: no exec, state and logs read', () async {
      final l = await run(access: 'sudo');
      expect(l.activeState, 'running');
      expect(l.configOk, isNull);
      expect(l.sectionErrors[WebLensSection.configTest], webDockerNeedsGroup);
      expect(l.statusCounts, {200: 1, 404: 1});
    }, skip: skip);

    test('a stopped container: state only, no exec', () async {
      final l = await run(access: 'plain', status: 'exited');
      expect(l.activeState, 'exited');
      expect(
        l.sectionErrors[WebLensSection.configTest],
        'Container is not running; config not read',
      );
    }, skip: skip);

    test('no docker access at all', () async {
      final l = await run(access: 'none');
      expect(l.sectionErrors[WebLensSection.active], webDockerDenied);
      expect(l.sectionErrors[WebLensSection.errorLog], webDockerDenied);
    }, skip: skip);
  });
}
