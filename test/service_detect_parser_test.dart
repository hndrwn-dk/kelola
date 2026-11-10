import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/service_detect_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detect_parser.dart';
import 'package:kelola/domain/services/service_detection.dart';

final _now = DateTime.utc(2026, 11, 10, 12);

DetectedService? _find(ServiceDetection d, ServiceId id) {
  for (final s in d.services) {
    if (s.id == id) {
      return s;
    }
  }
  return null;
}

String _fixture(String name) =>
    File('test/fixtures/services/$name').readAsStringSync();

void main() {
  test('systemd: nginx running and postgresql@16-main running detected', () {
    final d = parseServiceDetection(
      _fixture('systemctl_units_ubuntu.txt'),
      now: _now,
    );
    final nginx = _find(d, ServiceId.nginx)!;
    expect(nginx.state, ServiceState.running);
    expect(nginx.unit, 'nginx.service');
    expect(nginx.binaries['nginx'], '/usr/sbin/nginx');
    final pg = _find(d, ServiceId.postgres)!;
    expect(pg.state, ServiceState.running);
    // Umbrella and instance unit are both running: one entry, first listed.
    expect(pg.unit, 'postgresql.service');
    expect(d.services.map((s) => s.id).toSet(), {
      ServiceId.nginx,
      ServiceId.postgres,
    });
    expect(d.readAt, _now);
  });

  test('systemd failed state from ActiveState failed', () {
    final d = parseServiceDetection(
      '---UNITS---\nnginx.service failed failed\n---BIN---\n'
      'nginx /usr/sbin/nginx\n',
      now: _now,
    );
    expect(_find(d, ServiceId.nginx)!.state, ServiceState.failed);
  });

  test('systemd: running beats failed beats stopped across units', () {
    final d = parseServiceDetection(
      '---UNITS---\npostgresql.service inactive dead\n'
      'postgresql@15-main.service failed failed\n'
      'postgresql@16-main.service active running\n',
      now: _now,
    );
    expect(d.services, hasLength(1));
    expect(d.services.single.unit, 'postgresql@16-main.service');
    final d2 = parseServiceDetection(
      '---UNITS---\npostgresql.service inactive dead\n'
      'postgresql@15-main.service failed failed\n',
      now: _now,
    );
    expect(d2.services.single.state, ServiceState.failed);
    expect(d2.services.single.unit, 'postgresql@15-main.service');
  });

  test('openrc: rc-status started/stopped maps to running/stopped', () {
    final d = parseServiceDetection(
      _fixture('rc_status_alpine.txt'),
      now: _now,
    );
    final nginx = _find(d, ServiceId.nginx)!;
    expect(nginx.state, ServiceState.running);
    expect(nginx.unit, 'nginx');
    expect(nginx.version, '1.26.2');
    final pg = _find(d, ServiceId.postgres)!;
    expect(pg.state, ServiceState.stopped);
    expect(pg.unit, 'postgresql');
  });

  test('openrc: supervised line with uptime in the bracket still parses', () {
    final d = parseServiceDetection(
      '---UNITS---\n nginx                      [  started 00:01:23 (0) ]\n',
      now: _now,
    );
    expect(_find(d, ServiceId.nginx)!.state, ServiceState.running);
    expect(_find(d, ServiceId.nginx)!.unit, 'nginx');
  });

  test('openrc: crashed maps to failed; starting/stopping map to stopped', () {
    final d = parseServiceDetection(
      '---UNITS---\n nginx [  crashed  ]\n apache2 [  starting  ]\n'
      ' postgresql [  stopping  ]\n',
      now: _now,
    );
    expect(_find(d, ServiceId.nginx)!.state, ServiceState.failed);
    expect(_find(d, ServiceId.apache)!.state, ServiceState.stopped);
    expect(_find(d, ServiceId.postgres)!.state, ServiceState.stopped);
  });

  test('openrc: mysql service on a MariaDB host → single mariadb entry', () {
    final d = parseServiceDetection(
      '---UNITS---\n mysql [  started  ]\n'
      '---VERSION---\nmariadb mariadb from 11.4.2-MariaDB, client 15.2\n',
      now: _now,
    );
    expect(d.services.map((s) => s.id), [ServiceId.mariadb]);
    expect(d.services.single.state, ServiceState.running);
    expect(d.services.single.unit, 'mysql');
  });

  test('unknown init: binary only → installed', () {
    final d = parseServiceDetection(
      '---UNITS---\n---BIN---\napache2 /usr/sbin/apache2\n'
      '---VERSION---\napache Server version: Apache/2.4.57 (Debian)\n',
      now: _now,
    );
    final a = _find(d, ServiceId.apache)!;
    expect(a.state, ServiceState.installed);
    expect(a.unit, isNull);
    expect(a.binaries, {'apache2': '/usr/sbin/apache2'});
  });

  test('mysql.service whose version line says MariaDB → single mariadb entry', () {
    final d = parseServiceDetection(
      '---UNITS---\nmysql.service active running\nmariadb.service active running\n'
      '---BIN---\nmariadb /usr/bin/mariadb\nmysql /usr/bin/mysql\n'
      '---VERSION---\n'
      'mariadb mariadb from 11.4.2-MariaDB, client 15.2 for debian-linux-gnu\n'
      'mysql mysql from 11.4.2-MariaDB, client 15.2 for debian-linux-gnu\n',
      now: _now,
    );
    expect(d.services.map((s) => s.id), [ServiceId.mariadb]);
    expect(d.services.single.state, ServiceState.running);
    expect(d.services.single.version, '11.4.2');
  });

  test('mysqld.service without MariaDB in version → mysql only', () {
    final d = parseServiceDetection(
      '---UNITS---\nmysql.service active running\n'
      '---BIN---\nmysql /usr/bin/mysql\n'
      '---VERSION---\nmysql mysql  Ver 8.0.36 for Linux on x86_64 (MySQL)\n',
      now: _now,
    );
    expect(d.services.map((s) => s.id), [ServiceId.mysql]);
    expect(d.services.single.version, '8.0.36');
  });

  test('version lines parsed: nginx/1.24.0 → 1.24.0, Server version: Apache/2.4.57 → 2.4.57', () {
    final d = parseServiceDetection(
      '---UNITS---\nnginx.service active running\napache2.service active running\n'
      '---VERSION---\n'
      'nginx nginx version: nginx/1.24.0 (Ubuntu)\n'
      'apache Server version: Apache/2.4.57 (Ubuntu)\n',
      now: _now,
    );
    expect(_find(d, ServiceId.nginx)!.version, '1.24.0');
    expect(_find(d, ServiceId.apache)!.version, '2.4.57');
  });

  test('junk and missing sections → empty, no throw', () {
    for (final s in [
      '',
      'garbage',
      '---UNITS---',
      '---BIN---\n\u0000\u0001 \n---VERSION---\n???\n---PORTS---\nfoo\n',
      '---UNITS---\n.service\n x\n[ ]\n---PORTS---\n:\n',
    ]) {
      final d = parseServiceDetection(s, now: _now);
      expect(d.services, isEmpty, reason: s);
      expect(d.listeningPorts, isEmpty, reason: s);
    }
  });

  test('ports parsed from ss -Hltn local column incl. [::]:443', () {
    final d = parseServiceDetection(
      _fixture('systemctl_units_ubuntu.txt'),
      now: _now,
    );
    expect(d.listeningPorts, [22, 53, 80, 443, 5432]);
    final j = parseServiceDetection(
      '---PORTS---\n[::]:443\nbad\n0.0.0.0:99999\n0.0.0.0:x\n*:8080\n',
      now: _now,
    );
    expect(j.listeningPorts, [443, 8080]);
  });

  group('ServiceDetectProbe command', () {
    HostFacts facts(InitSystem init) =>
        HostFacts.undiscovered.copyWith(init: init);
    const probe = ServiceDetectProbe();

    test('metadata', () {
      expect(probe.risk, RiskLevel.read);
      expect(probe.needsSudo, isFalse);
      expect(probe.timeout, const Duration(seconds: 10));
      expect(probe.auditTitle, 'Detected services');
    });

    test('openrc uses rc-status -a, not systemctl', () {
      final c = probe.command(facts(InitSystem.openrc));
      expect(c, contains('rc-status -a'));
      expect(c, isNot(contains('systemctl')));
    });

    test('systemd lists all service units', () {
      final c = probe.command(facts(InitSystem.systemd));
      expect(c, contains('list-units --type=service --all'));
    });

    test('unknown init has neither', () {
      final c = probe.command(facts(InitSystem.unknown));
      expect(c, isNot(contains('systemctl')));
      expect(c, isNot(contains('rc-status')));
    });

    test('never asks ss for owning processes; built from catalog', () {
      for (final i in InitSystem.values) {
        final c = probe.command(facts(i));
        expect(c, isNot(contains('ss -p')));
        expect(c, isNot(contains('-ltnp')));
        expect(c, isNot(contains('sudo')));
        expect(c, contains('ss -Hltn'));
        for (final d in kServiceCatalog) {
          for (final b in d.binaries) {
            expect(c, contains(b));
          }
        }
        expect(c, contains('---VERSION---'));
      }
    });

    test('sbin dirs are appended to PATH before any command -v', () {
      const line = 'PATH="\$PATH:/usr/local/sbin:/usr/sbin:/sbin"; export PATH';
      for (final i in InitSystem.values) {
        final c = probe.command(facts(i));
        expect(c, contains(line));
        expect(c.indexOf(line), lessThan(c.indexOf('command -v')));
        expect(line.allMatches(c), hasLength(1));
      }
    });

    test('a binary only in an sbin dir is detected (executed)', () async {
      final dir = await Directory.systemTemp.createTemp('kelola_detect_sbin');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/nginx')
          .writeAsStringSync('#!/bin/sh\necho "nginx version: nginx/1.24.0" >&2\n');
      await Process.run('chmod', ['+x', '${dir.path}/nginx']);
      // The temp dir stands in for /usr/sbin; the login PATH has no sbin.
      final c = probe.command(facts(InitSystem.unknown)).replaceFirst(
        ':/usr/local/sbin:/usr/sbin:/sbin"',
        ':${dir.path}"',
      );
      final r = await Process.run(
        'sh',
        ['-c', c],
        environment: {'PATH': '/usr/bin:/bin'},
      );
      final d = probe.parse(r.stdout as String, r.stderr as String, r.exitCode);
      final nginx = d.services.singleWhere((s) => s.id == ServiceId.nginx);
      expect(nginx.binaries['nginx'], '${dir.path}/nginx');
      expect(nginx.version, '1.24.0');
    }, skip: Platform.isWindows);

    test('parse delegates to the parser', () {
      final r = probe.parse(
        '---UNITS---\nnginx.service active running\n',
        '',
        0,
      );
      expect(r.services.single.id, ServiceId.nginx);
    });
  });
}
