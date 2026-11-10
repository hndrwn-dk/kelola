import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/domain/services/web_lens_parser.dart';
import 'package:kelola/domain/sudo_hint.dart';

String fixture(String name) =>
    File('test/fixtures/services/$name').readAsStringSync();

/// Host output lines, as the probe prints them (`|` prefix).
List<String> data(String text) {
  final t = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  return [for (final l in t.split('\n')) '|$l'];
}

final now = DateTime.utc(2026, 11, 10, 12);

const ubuntu = HostFacts(
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

const rocky = HostFacts(
  osId: 'rocky',
  osVersionId: '9.4',
  init: InitSystem.systemd,
  systemdVersion: 252,
  pkg: PackageManager.dnf,
  fw: FirewallBackend.firewalld,
  hasJournald: true,
  journalReadable: true,
  arch: 'x86_64',
);

/// A complete, healthy nginx read built from the real captures.
String nginxOutput({
  List<String>? active,
  List<String>? conftest,
  List<String>? dump,
  List<String>? certs,
  List<String>? errlog,
  List<String>? access,
}) {
  return [
    '---TOOLS---',
    '|openssl /usr/bin/openssl',
    '|tail /usr/bin/tail',
    '---ACTIVE---',
    ...active ?? ['|active'],
    '---CONFTEST---',
    ...conftest ??
        [
          '|nginx: the configuration file /etc/nginx/nginx.conf syntax is ok',
          '|nginx: configuration file /etc/nginx/nginx.conf test is successful',
          '@rc=0',
        ],
    '---DUMP---',
    ...dump ?? data(fixture('nginx_T_ubuntu.txt')),
    '---CERTS---',
    ...certs ??
        [
          '@cert=/etc/ssl/certs/soon.crt',
          '@read=ok',
          ...data(fixture('openssl_enddate.txt')),
          '@done=1',
        ],
    '---ERRLOG---',
    ...errlog ??
        [
          '@path=/var/log/nginx/error.log',
          '@read=ok',
          '|2026/11/10 01:31:42 [emerg] 31594#31594: socket() [::]:80 failed',
        ],
    '---ACCESS---',
    ...access ??
        [
          '@path=/var/log/nginx/access.log',
          '@read=ok',
          ...data(fixture('nginx_access_tail.txt')),
        ],
  ].join('\n');
}

void main() {
  group('parseWebLens', () {
    test('cert notAfter/subject/SAN parsed per path', () {
      final out = nginxOutput(
        certs: [
          '@cert=/etc/ssl/certs/soon.crt',
          '@read=ok',
          ...data(fixture('openssl_enddate.txt')),
          '@cert=/etc/ssl/certs/nosan.pem',
          '@read=ok',
          '|notAfter=Nov 13 01:45:03 2026 GMT',
          '|subject=O = "Acme, Inc", CN = nosan.lab',
          '@cert=/etc/ssl/certs/old.pem',
          '@read=ok',
          '|notAfter=Jan  2 03:04:05 2027 GMT',
          '|subject= /C=US/O=Old/CN=old.lab',
          '|X509v3 Subject Alternative Name: ',
          '|    DNS:old.lab, IP Address:10.0.0.1, email:a@b.c, DNS:*.old.lab',
          '@cert=/etc/ssl/certs/gone.pem',
          '@read=fail',
          '@cert=/etc/ssl/certs/junk.pem',
          '@read=ok',
          '|notAfter=not a date',
          '|subject=',
          '@done=1',
        ],
      );
      final lens = parseWebLens(out, id: ServiceId.nginx, now: now);
      final soon = lens.certsByPath['/etc/ssl/certs/soon.crt']!;
      expect(soon.notAfter, DateTime.utc(2026, 11, 15, 1, 32));
      expect(soon.subjectCn, 'soon.lab');
      expect(soon.sans, ['soon.lab', 'www.soon.lab']);
      expect(soon.daysLeft(now), 4);

      final nosan = lens.certsByPath['/etc/ssl/certs/nosan.pem']!;
      expect(nosan.notAfter, DateTime.utc(2026, 11, 13, 1, 45, 3));
      expect(nosan.subjectCn, 'nosan.lab');
      expect(nosan.sans, isEmpty);

      final old = lens.certsByPath['/etc/ssl/certs/old.pem']!;
      expect(old.notAfter, DateTime.utc(2027, 1, 2, 3, 4, 5));
      expect(old.subjectCn, 'old.lab');
      expect(old.sans, ['old.lab', '*.old.lab']);

      final gone = lens.certsByPath['/etc/ssl/certs/gone.pem']!;
      expect(gone.notAfter, isNull);
      final junk = lens.certsByPath['/etc/ssl/certs/junk.pem']!;
      expect(junk.notAfter, isNull);
      expect(junk.subjectCn, isNull);
      expect(lens.sectionErrors[WebLensSection.certs], contains('2 of 5'));
      // Vhosts come from the dump either way.
      expect(lens.vhosts, hasLength(3));
      expect(lens.toolPaths, {
        'openssl': '/usr/bin/openssl',
        'tail': '/usr/bin/tail',
      });
    });

    test("status buckets parsed with junk and '-' lines", () {
      final lens = parseWebLens(nginxOutput(), id: ServiceId.nginx, now: now);
      expect(lens.statusCounts, {200: 30, 404: 4, 500: 4, 502: 1});
      expect(lens.accessLogPath, '/var/log/nginx/access.log');
      expect(lens.sectionErrors.containsKey(WebLensSection.access), isFalse);

      final junk = parseWebLens(
        nginxOutput(
          access: [
            '@path=/var/log/nginx/access.log',
            '@read=ok',
            '|      7 -',
            '|   12x 200',
            '|      3 2OO',
            '|      5 99',
            '|      5 600',
            '|  99999999999999999999 200',
            '|garbage',
            '|',
            '|      2 301',
            '|      1 301',
          ],
        ),
        id: ServiceId.nginx,
        now: now,
      );
      expect(junk.statusCounts, {301: 3});
    });

    test('each empty section → sectionErrors entry not empty list', () {
      final out = [
        '---TOOLS---',
        '---ACTIVE---',
        '---CONFTEST---',
        '---DUMP---',
        '---CERTS---',
        '---ERRLOG---',
        '@path=/var/log/nginx/error.log',
        '@read=fail',
        '---ACCESS---',
        '@path=/var/log/nginx/access.log',
        '@read=fail',
      ].join('\n');
      final lens = parseWebLens(out, id: ServiceId.nginx, now: now);
      expect(lens.activeState, isNull);
      expect(lens.configOk, isNull);
      for (final s in [
        WebLensSection.active,
        WebLensSection.configTest,
        WebLensSection.dump,
        WebLensSection.errorLog,
        WebLensSection.access,
      ]) {
        expect(lens.sectionErrors[s], isNotNull, reason: s.name);
        expect(lens.sectionErrors[s], isNotEmpty, reason: s.name);
      }
      expect(
        lens.sectionErrors[WebLensSection.errorLog],
        contains('error log'),
      );
      expect(lens.errorLogPath, '/var/log/nginx/error.log');

      // Missing markers entirely (junk / cut output): still errors, no throw.
      for (final junk in ['', 'garbage\n---\n|x', '---CERTS---\n|x']) {
        final l = parseWebLens(junk, id: ServiceId.apache, now: now);
        expect(l.sectionErrors.keys, containsAll(WebLensSection.values));
        expect(l.vhosts, isEmpty);
        expect(l.statusCounts, isEmpty);
      }

      // A readable but empty log is data (no lines), not an error.
      final quiet = parseWebLens(
        nginxOutput(errlog: ['@path=/var/log/nginx/error.log', '@read=ok']),
        id: ServiceId.nginx,
        now: now,
      );
      expect(quiet.errorLogTail, isEmpty);
      expect(quiet.sectionErrors.containsKey(WebLensSection.errorLog), isFalse);
    });

    test('DUMP failed both legs → SudoRequiredException(webServices)', () {
      final out = nginxOutput(conftest: ['@rc=nosudo'], dump: []);
      expect(
        () => parseWebLens(out, id: ServiceId.nginx, now: now),
        throwsA(
          isA<SudoRequiredException>()
              .having((e) => e.context.kind, 'kind', SudoHintKind.webServices)
              .having((e) => e.context.target, 'service', 'nginx'),
        ),
      );
      expect(
        () => parseWebLens(out, id: ServiceId.apache, now: now),
        throwsA(
          isA<SudoRequiredException>()
              .having((e) => e.context.kind, 'kind', SudoHintKind.webServices)
              .having((e) => e.context.target, 'service', 'apache'),
        ),
      );
      // The hint survives the exception wire format.
      try {
        parseWebLens(out, id: ServiceId.nginx, now: now);
      } on SudoRequiredException catch (e) {
        final ctx = SudoHintContext.tryParse(e.message);
        expect(ctx.kind, SudoHintKind.webServices);
        expect(ctx.target, 'nginx');
      }

      // Config test ran and failed: real nginx prints no -T dump then. That is
      // a dump section error, not a sudo problem.
      final failed = parseWebLens(
        nginxOutput(
          conftest: [
            '|nginx: [emerg] unknown directive "bogus" in /etc/nginx/conf.d/x.conf:3',
            '|nginx: configuration file /etc/nginx/nginx.conf test failed',
            '@rc=1',
          ],
          dump: [],
        ),
        id: ServiceId.nginx,
        now: now,
      );
      expect(failed.configOk, isFalse);
      expect(failed.vhosts, isEmpty);
      expect(
        failed.sectionErrors[WebLensSection.dump],
        contains('Config test failed'),
      );
    });

    test('nosudo config test is unknown, never a failed config', () {
      final lens = parseWebLens(
        nginxOutput(conftest: ['@rc=nosudo']),
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.configOk, isNull);
      expect(lens.configErrors, isEmpty);
      expect(lens.sectionErrors[WebLensSection.configTest], contains('sudo'));
      expect(lens.vhosts, hasLength(3));
    });

    test('cert section fails but vhosts still present', () {
      for (final certs in [
        <String>[],
        ['@cert=/etc/ssl/certs/soon.crt', '@read=fail', '@done=1'],
      ]) {
        final lens = parseWebLens(
          nginxOutput(certs: certs),
          id: ServiceId.nginx,
          now: now,
        );
        expect(lens.vhosts, hasLength(3));
        expect(lens.vhosts.first.certPath, '/etc/ssl/certs/soon.crt');
        expect(lens.configOk, isTrue);
        expect(lens.statusCounts, isNotEmpty);
      }
      // CERTS marker missing entirely (output cut): section error, vhosts kept.
      final cut = nginxOutput().split('---CERTS---').first;
      final lens = parseWebLens(cut, id: ServiceId.nginx, now: now);
      expect(lens.vhosts, hasLength(3));
      expect(lens.sectionErrors[WebLensSection.certs], isNotNull);
      final unreadable = parseWebLens(
        nginxOutput(
          certs: ['@cert=/etc/ssl/certs/soon.crt', '@read=fail', '@done=1'],
        ),
        id: ServiceId.nginx,
        now: now,
      );
      expect(
        unreadable.certsByPath['/etc/ssl/certs/soon.crt']!.notAfter,
        isNull,
      );
      expect(unreadable.sectionErrors[WebLensSection.certs], isNotNull);
    });

    test('configOk false and errors kept when rc≠0', () {
      final lens = parseWebLens(
        nginxOutput(
          conftest: [
            '|nginx: [emerg] unknown directive "bogus" in /etc/nginx/conf.d/x.conf:3',
            '|nginx: configuration file /etc/nginx/nginx.conf test failed',
            '@rc=1',
          ],
        ),
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.configOk, isFalse);
      expect(lens.configErrors, [
        'nginx: [emerg] unknown directive "bogus" in /etc/nginx/conf.d/x.conf:3',
        'nginx: configuration file /etc/nginx/nginx.conf test failed',
      ]);
      final ok = parseWebLens(nginxOutput(), id: ServiceId.nginx, now: now);
      expect(ok.configOk, isTrue);
      expect(ok.configErrors, isEmpty);
    });

    test('active state, error log tail and truncated dump', () {
      final lens = parseWebLens(nginxOutput(), id: ServiceId.nginx, now: now);
      expect(lens.activeState, 'active');
      expect(lens.errorLogPath, '/var/log/nginx/error.log');
      expect(lens.errorLogTail, hasLength(1));
      expect(lens.readAt, now);
      final rc = parseWebLens(
        nginxOutput(active: ['|rc-service: x', '| * status: started']),
        id: ServiceId.nginx,
        now: now,
      );
      expect(rc.activeState, 'started');
      final cut = parseWebLens(
        nginxOutput(dump: data(fixture('nginx_T_truncated.txt'))),
        id: ServiceId.nginx,
        now: now,
      );
      expect(cut.sectionErrors[WebLensSection.dump], contains('truncated'));
    });

    test('host text cannot fake a section marker', () {
      final lens = parseWebLens(
        nginxOutput(
          errlog: [
            '@path=/var/log/nginx/error.log',
            '@read=ok',
            '|---ACCESS---',
            '|@path=/etc/shadow',
            '|      999 500',
          ],
        ),
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.accessLogPath, '/var/log/nginx/access.log');
      expect(lens.statusCounts[500], 4);
      expect(lens.errorLogTail, [
        '---ACCESS---',
        '@path=/etc/shadow',
        '      999 500',
      ]);
    });

    test('apache dump parsed with -S', () {
      final lens = parseWebLens(
        nginxOutput(
          dump: data(fixture('httpd_S_rocky.txt')),
          certs: ['@done=1'],
        ),
        id: ServiceId.apache,
        now: now,
      );
      expect(lens.vhosts, isNotEmpty);
      expect(lens.sectionErrors.containsKey(WebLensSection.dump), isFalse);
      // The vhost files from -S, without their line numbers (fix 1).
      expect(lens.configFiles, [
        '/etc/httpd/conf.d/ssl.conf',
        '/etc/httpd/conf.d/other.conf',
        '/etc/httpd/conf.d/site.conf',
      ]);
    });

    test('nginx config files come from the dump sections', () {
      final lens = parseWebLens(nginxOutput(), id: ServiceId.nginx, now: now);
      expect(lens.configFiles, [
        '/etc/nginx/nginx.conf',
        '/etc/nginx/mime.types',
        '/etc/nginx/conf.d/soon.conf',
        '/etc/nginx/sites-enabled/default',
      ]);
      // No dump: none known.
      final none = parseWebLens(
        nginxOutput(dump: const []),
        id: ServiceId.nginx,
        now: now,
      );
      expect(none.configFiles, isEmpty);
    });

    test('unsafe tool and log paths are dropped', () {
      final lens = parseWebLens(
        [
          '---TOOLS---',
          '|openssl /usr/bin/open ssl',
          '|tail relative/tail',
          '---ERRLOG---',
          '@path=/var/log/../shadow',
          '@read=fail',
        ].join('\n'),
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.toolPaths, isEmpty);
      expect(lens.errorLogPath, isNull);
    });
  });

  // Fix 2: `@stat=<owner> <group> <mode>` in the log sections and
  // `@groups=<names>` in TOOLS, so the lens can suggest the adm group.
  group('log stat and login groups', () {
    String out({List<String>? tools, List<String>? err, List<String>? acc}) {
      final base = nginxOutput(
        errlog: err ??
            ['@path=/var/log/nginx/error.log', '@read=fail'],
        access: acc ??
            ['@path=/var/log/nginx/access.log', '@read=fail'],
      );
      return tools == null
          ? base
          : base.replaceFirst('---TOOLS---', ['---TOOLS---', ...tools].join('\n'));
    }

    WebLens parse(String s) => parseWebLens(s, id: ServiceId.nginx, now: now);

    test('adm with group read', () {
      final l = parse(
        out(
          tools: ['@groups=deploy sudo'],
          err: [
            '@path=/var/log/nginx/error.log',
            '@stat=www-data adm 640',
            '@read=fail',
          ],
          acc: [
            '@path=/var/log/nginx/access.log',
            '@stat=root adm 0640',
            '@read=fail',
          ],
        ),
      );
      expect(l.errorLogStat!.owner, 'www-data');
      expect(l.errorLogStat!.group, 'adm');
      expect(l.errorLogStat!.mode, '640');
      expect(l.errorLogStat!.groupReadable, isTrue);
      expect(l.accessLogStat!.owner, 'root');
      expect(l.accessLogStat!.groupReadable, isTrue);
      expect(l.loginGroups, ['deploy', 'sudo']);
      // Still a section error each; findings unchanged.
      expect(l.sectionErrors[WebLensSection.errorLog], isNotNull);
      expect(l.sectionErrors[WebLensSection.access], isNotNull);
    });

    test('adm without group read', () {
      final l = parse(
        out(
          err: [
            '@path=/var/log/nginx/error.log',
            '@stat=root adm 600',
            '@read=fail',
          ],
          acc: [
            '@path=/var/log/nginx/access.log',
            '@stat=root adm 2604',
            '@read=fail',
          ],
        ),
      );
      expect(l.errorLogStat!.group, 'adm');
      expect(l.errorLogStat!.groupReadable, isFalse);
      // setgid digit first: the group digit is still the middle one of the
      // last three.
      expect(l.accessLogStat!.mode, '2604');
      expect(l.accessLogStat!.groupReadable, isFalse);
    });

    test('another group (Alpine: nginx owns its logs)', () {
      final l = parse(
        out(
          tools: ['@groups=deploy wheel'],
          err: [
            '@path=/var/log/nginx/error.log',
            '@stat=nginx nginx 640',
            '@read=fail',
          ],
        ),
      );
      expect(l.errorLogStat!.group, 'nginx');
      expect(l.errorLogStat!.groupReadable, isTrue);
      expect(l.accessLogStat, isNull);
    });

    test('missing lines: stat and groups unknown', () {
      final l = parse(out());
      expect(l.errorLogStat, isNull);
      expect(l.accessLogStat, isNull);
      expect(l.loginGroups, isNull);
    });

    test('junk is ignored, never guessed', () {
      for (final bad in const [
        'root adm',
        'root adm 640 x',
        'root adm 9x0',
        'root adm 64',
        'root adm 06400',
        'r;oot adm 640',
        r'root a$m 640',
        'root  adm 640',
        '',
      ]) {
        final l = parse(
          out(
            err: [
              '@path=/var/log/nginx/error.log',
              '@stat=$bad',
              '@read=fail',
            ],
          ),
        );
        expect(l.errorLogStat, isNull, reason: bad);
      }
      final long = 'a' * 65;
      expect(
        parse(
          out(
            err: [
              '@path=/var/log/nginx/error.log',
              '@stat=$long adm 640',
              '@read=fail',
            ],
          ),
        ).errorLogStat,
        isNull,
      );
      // Host text (`|` prefix) never counts as a meta line.
      final hostText = parse(
        out(
          tools: ['|@groups=adm'],
          err: [
            '@path=/var/log/nginx/error.log',
            '|@stat=root adm 640',
            '@read=fail',
          ],
        ),
      );
      expect(hostText.errorLogStat, isNull);
      expect(hostText.loginGroups, isNull);
      // Bad names in the group list are dropped; the rest kept.
      expect(
        parse(out(tools: [r'@groups=deploy $(x) a;b sudo'])).loginGroups,
        ['deploy', 'sudo'],
      );
      // Nothing usable: unknown, not "no groups".
      expect(parse(out(tools: ['@groups='])).loginGroups, isNull);
      expect(parse(out(tools: [r'@groups=$(x) a;b'])).loginGroups, isNull);
      // A meta line in the wrong section does not count.
      expect(
        parse(
          out(
            err: [
              '@path=/var/log/nginx/error.log',
              '@groups=deploy',
              '@read=fail',
            ],
          ),
        ).loginGroups,
        isNull,
      );
    });
  });

  group('real probe runs (nginx 1.24, Apache 2.4.58, Ubuntu, no systemd)', () {
    test('nginx as root', () {
      final lens = parseWebLens(
        fixture('web_lens_nginx_ubuntu.txt'),
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.configOk, isTrue);
      expect(lens.vhosts.map((v) => v.serverNames.first), [
        'soon.lab',
        'nocert.lab',
        '_',
      ]);
      final cert = lens.certsByPath['/etc/ssl/certs/soon.crt']!;
      expect(cert.daysLeft(now), 4);
      expect(cert.sans, ['soon.lab', 'www.soon.lab']);
      expect(lens.errorLogTail, hasLength(4));
      expect(lens.statusCounts, {200: 30, 404: 4, 500: 4});
      // No systemctl in the container: honest section error, not a state.
      expect(lens.activeState, isNull);
      expect(lens.sectionErrors.keys, [WebLensSection.active]);
      expect(lens.toolPaths, {
        'openssl': '/usr/bin/openssl',
        'tail': '/usr/bin/tail',
      });
      final levels = [for (final f in lens.findings) (f.level, f.message)];
      expect(levels, [
        (WebFindingLevel.failed, 'Certificate expires in 4 days'),
        (WebFindingLevel.warning, 'Listens on 443 without a certificate'),
      ]);
    });

    test('apache as root', () {
      final lens = parseWebLens(
        fixture('web_lens_apache_ubuntu.txt'),
        id: ServiceId.apache,
        now: now,
      );
      expect(lens.configOk, isTrue);
      expect(lens.vhosts.single.serverNames, ['127.0.0.1']);
      expect(lens.certsByPath.keys, ['/etc/ssl/certs/ssl-cert-snakeoil.pem']);
      expect(lens.errorLogPath, '/var/log/apache2/error.log');
      expect(lens.accessLogPath, '/var/log/apache2/access.log');
      expect(lens.errorLogTail, isEmpty);
      expect(lens.statusCounts, isEmpty);
      expect(lens.sectionErrors.keys, [WebLensSection.active]);
    });

    test('nginx as a user without sudo throws the lens sudo hint', () {
      expect(
        () => parseWebLens(
          fixture('web_lens_nginx_nosudo.txt'),
          id: ServiceId.nginx,
          now: now,
        ),
        throwsA(
          isA<SudoRequiredException>().having(
            (e) => e.context.kind,
            'kind',
            SudoHintKind.webServices,
          ),
        ),
      );
    });
  });

  test('webServices hint points at the lens grant, not Enable', () {
    final hint = kelolaSudoHint(
      user: 'deploy',
      context: SudoHintContext.webServices(service: 'nginx'),
    );
    expect(hint.body, contains('Grant read access for this lens'));
    expect(hint.body, contains('/etc/sudoers.d/kelola-web'));
    expect(hint.body, isNot(contains('Use Enable')));
    expect(hint.snippet, contains('deploy ALL=(root) NOPASSWD: <nginx> -T'));
    expect(hint.snippet, isNot(contains('*')));
    final apache = kelolaSudoHint(
      context: SudoHintContext.webServices(service: 'apache'),
    );
    expect(apache.snippet, contains('<apachectl> -S'));
    // An unknown name from the wire is never echoed.
    final odd = kelolaSudoHint(
      context: SudoHintContext.webServices(service: 'x; rm -rf /'),
    );
    expect(odd.body + odd.snippet, isNot(contains('rm -rf')));
  });

  group('WebLensProbe command', () {
    const nginx = WebLensProbe(
      id: ServiceId.nginx,
      binaries: {'nginx': '/usr/sbin/nginx'},
      unit: 'nginx.service',
    );
    const apache = WebLensProbe(
      id: ServiceId.apache,
      binaries: {
        'apache2': '/usr/sbin/apache2',
        'apache2ctl': '/usr/sbin/apache2ctl',
      },
      unit: 'apache2.service',
    );

    test('metadata', () {
      expect(nginx.risk, RiskLevel.read);
      expect(nginx.needsSudo, isFalse);
      expect(nginx.timeout, const Duration(seconds: 30));
      expect(nginx.auditTitle, 'Read nginx');
      expect(apache.auditTitle, 'Read Apache');
    });

    test('command contains -t and -T for nginx', () {
      final cmd = nginx.command(ubuntu);
      expect(cmd, contains("B='/usr/sbin/nginx'"));
      expect(cmd, contains(r'"$B" -t'));
      expect(cmd, contains(r'try "$B" -T'));
      for (final m in [
        '---TOOLS---',
        '---ACTIVE---',
        '---CONFTEST---',
        '---DUMP---',
        '---CERTS---',
        '---ERRLOG---',
        '---ACCESS---',
      ]) {
        expect(cmd, contains('echo $m'));
      }
      expect(cmd, contains("systemctl is-active 'nginx.service'"));
      expect(cmd, contains("e='/var/log/nginx/error.log'"));
      expect(cmd, contains("a='/var/log/nginx/access.log'"));
    });

    test('apache uses detected ctl path and -S', () {
      final cmd = apache.command(ubuntu);
      expect(cmd, contains("B='/usr/sbin/apache2ctl'"));
      expect(cmd, contains(r'try "$B" -S'));
      expect(cmd, contains(r'"$B" -t'));
      expect(cmd, isNot(contains('/usr/sbin/apache2\'')));
      expect(cmd, contains("'/etc/apache2'"));
      expect(cmd, contains("e='/var/log/apache2/error.log'"));
      final rh = const WebLensProbe(
        id: ServiceId.apache,
        binaries: {
          'httpd': '/usr/sbin/httpd',
          'apachectl': '/usr/sbin/apachectl',
        },
        unit: 'httpd.service',
      ).command(rocky);
      expect(rh, contains("B='/usr/sbin/apachectl'"));
      expect(rh, contains("'/etc/httpd'"));
      expect(rh, contains("a='/var/log/httpd/access_log'"));
      // Nothing detected: the bare catalog name, never a host string.
      final bare = const WebLensProbe(
        id: ServiceId.apache,
        binaries: {},
      ).command(rocky);
      expect(bare, contains("B='apachectl'"));
    });

    test('openssl only receives ssl_certificate paths', () {
      for (final p in [nginx, apache]) {
        final cmd = p.command(ubuntu);
        expect(cmd, isNot(contains('ssl_certificate_key')));
        expect(cmd, isNot(contains('SSLCertificateKeyFile')));
        expect(cmd, isNot(contains('.key')));
        expect(cmd, isNot(contains('eval')));
        expect(
          cmd,
          contains(
            r'try "$O" x509 -noout -enddate -subject -ext subjectAltName -in "$p"',
          ),
        );
      }
      // The directive is matched as the whole first token, never a prefix.
      expect(nginx.command(ubuntu), contains(r'tolower($1) == k'));
      expect(nginx.command(ubuntu), contains('pick ssl_certificate 50 |'));
      expect(apache.command(ubuntu), contains('pick sslcertificatefile 50 |'));
    });

    test('every privileged read is wrapped as plain-then-sudo -n', () {
      for (final p in [nginx, apache]) {
        final cmd = p.command(ubuntu);
        expect(
          cmd,
          contains(r'try() { "$@" 2>/dev/null || sudo -n "$@" 2>/dev/null; }'),
        );
        // Config test: plain first, then the same argv under sudo -n.
        expect(cmd, contains(r'o=$("$B" -t 2>&1)'));
        expect(cmd, contains(r'o=$(sudo -n "$B" -t 2>&1)'));
        expect(cmd, contains(r'try "$T" -n 60 "$e"'));
        expect(cmd, contains(r'try "$T" -n 2000 "$a"'));
        // No bare privileged read outside try / the config test.
        final calls = cmd.replaceAll('command -v sudo ', '');
        expect(RegExp(r'sudo (?!-n )').hasMatch(calls), isFalse);
        expect(cmd, isNot(contains('sudo -S')));
      }
    });

    // Fix 2: the log stat and the login's groups are plain reads, never
    // through sudo or try.
    test('log stat and id -nG run plain, never via sudo or try', () {
      for (final p in [nginx, apache]) {
        for (final f in [ubuntu, rocky]) {
          final cmd = p.command(f);
          expect(cmd, contains(r'''stat -L -c '%U %G %a' "$e" 2>/dev/null'''));
          expect(cmd, contains(r'''stat -L -c '%U %G %a' "$a" 2>/dev/null'''));
          expect('id -nG 2>/dev/null'.allMatches(cmd), hasLength(1));
          final lines = [
            for (final l in cmd.split('\n'))
              if (l.contains('stat -L -c') || l.contains('id -nG')) l,
          ];
          expect(lines, hasLength(3));
          for (final l in lines) {
            expect(l, isNot(contains('sudo')), reason: l);
            expect(l, isNot(contains('try')), reason: l);
          }
          // Every sudo invocation is still sudo -n.
          final calls = cmd.replaceAll('command -v sudo ', '');
          expect(RegExp(r'sudo (?!-n )').hasMatch(calls), isFalse);
          expect(cmd, isNot(contains('usermod')));
        }
      }
    });

    test('a hostile stat or id cannot forge a marker (executed)', () async {
      final dir = await Directory.systemTemp.createTemp('kelola_lens_forge');
      addTearDown(() => dir.delete(recursive: true));
      Future<void> stub(String name, String body) async {
        File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
        await Process.run('chmod', ['+x', '${dir.path}/$name']);
      }

      await stub('stat', r"printf 'root adm 640\n---ACCESS---\n@read=ok\n|200\n'");
      await stub('id', r"printf 'deploy\n---ERRLOG---\n@stat=root adm 640\n'");
      await stub('nginx', 'exit 0');
      final probe = WebLensProbe(
        id: ServiceId.nginx,
        binaries: {'nginx': '${dir.path}/nginx'},
      );
      final r = await Process.run(
        'sh',
        ['-c', probe.command(ubuntu)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      final out = r.stdout as String;
      expect('---ACCESS---'.allMatches(out), hasLength(1), reason: out);
      expect('---ERRLOG---'.allMatches(out), hasLength(1), reason: out);
      expect(out, contains('@groups=deploy\n'));
      expect(RegExp(r'^@stat=root adm 640$', multiLine: true).allMatches(out),
          hasLength(2));
    }, skip: Platform.isWindows);

    group('log stat on a real tree (executed, dash and busybox)', () {
      String? bbDir;
      late Directory dir;
      final isRoot =
          !Platform.isWindows &&
          (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
      final hasSetpriv =
          !Platform.isWindows &&
          Process.runSync('sh', ['-c', 'command -v setpriv']).exitCode == 0;
      final hasDash =
          !Platform.isWindows &&
          Process.runSync('sh', ['-c', 'command -v dash']).exitCode == 0;

      setUpAll(() {
        if (Platform.isWindows) return;
        final which = Process.runSync('sh', ['-c', 'command -v busybox']);
        final bb = (which.stdout as String).trim();
        if (which.exitCode != 0 || bb.isEmpty) return;
        final d = Directory.systemTemp.createTempSync('kelola_bb_lens');
        final r = Process.runSync(bb, ['--install', '-s', d.path]);
        if (r.exitCode == 0 && File('${d.path}/stat').existsSync()) {
          bbDir = d.path;
        } else {
          d.deleteSync(recursive: true);
        }
      });

      tearDownAll(() {
        final d = bbDir;
        if (d != null) Directory(d).deleteSync(recursive: true);
      });

      setUp(() {
        if (Platform.isWindows) return;
        dir = Directory.systemTemp.createTempSync('kelola_lens_stat');
        Process.runSync('chmod', ['755', dir.path]);
      });

      tearDown(() {
        if (Platform.isWindows) return;
        Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
        dir.deleteSync(recursive: true);
      });

      void stub(String name, String body) {
        File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
        Process.runSync('chmod', ['755', '${dir.path}/$name']);
      }

      /// The section of [stdout] after marker [name], up to the next one.
      List<String> section(String stdout, String name) {
        final lines = stdout.split('\n');
        final i = lines.indexOf('---$name---');
        if (i < 0) return const [];
        final rest = lines.sublist(i + 1);
        final j = rest.indexWhere((l) => RegExp(r'^---[A-Z]+---$').hasMatch(l));
        return j < 0 ? rest : rest.sublist(0, j);
      }

      for (final shell in const ['dash', 'busybox']) {
        test('$shell: @stat for a readable dir, nothing for an untraversable one',
            () async {
          if (shell == 'busybox' && bbDir == null) {
            markTestSkipped('busybox is not installed here');
            return;
          }
          if (shell == 'dash' && !hasDash) {
            markTestSkipped('dash is not installed here');
            return;
          }
          if (isRoot && !hasSetpriv) {
            markTestSkipped('running as root without setpriv: cannot drop '
                'to nobody, and root reads every file');
            return;
          }
          // Debian layout: the log dir is traversable, the log itself
          // root:adm 0640. A second log sits in a directory nobody can
          // traverse.
          final logs = Directory('${dir.path}/logs')..createSync();
          final locked = Directory('${dir.path}/locked')..createSync();
          final err = File('${logs.path}/error.log')
            ..writeAsStringSync('x\n');
          final acc = File('${locked.path}/access.log')
            ..writeAsStringSync('x\n');
          for (final f in [err, acc]) {
            Process.runSync('chmod', ['640', f.path]);
            if (isRoot) Process.runSync('chgrp', ['adm', f.path]);
          }
          Process.runSync('chmod', ['755', logs.path]);
          Process.runSync('chmod', ['000', locked.path]);
          stub('nginx', '''
case "\$1" in
  -t) echo "nginx: test is successful" >&2 ;;
  -T) printf '%s\\n' 'error_log ${err.path};' 'access_log ${acc.path};' ;;
esac''');
          stub('sudo', 'echo "sudo: a password is required" >&2\nexit 1');
          final probe = WebLensProbe(
            id: ServiceId.nginx,
            binaries: {'nginx': '${dir.path}/nginx'},
          );
          final script = probe.command(ubuntu);
          final path = shell == 'busybox'
              ? '${dir.path}:$bbDir'
              : '${dir.path}:/usr/bin:/bin';
          final argv = shell == 'busybox'
              ? ['busybox', 'sh', '-c', script]
              : ['dash', '-c', script];
          final cmd = isRoot
              ? [
                  'setpriv',
                  '--reuid=nobody',
                  '--regid=${(Process.runSync('id', ['-g', 'nobody']).stdout as String).trim()}',
                  '--clear-groups',
                  '--',
                  'env',
                  'PATH=$path',
                  ...argv,
                ]
              : ['env', 'PATH=$path', ...argv];
          final r = await Process.run(cmd.first, cmd.sublist(1));
          final stdout = r.stdout as String;
          final errSec = section(stdout, 'ERRLOG');
          final accSec = section(stdout, 'ACCESS');
          final group = isRoot
              ? 'adm'
              : (Process.runSync('id', ['-gn']).stdout as String).trim();
          final owner = isRoot
              ? 'root'
              : (Process.runSync('id', ['-un']).stdout as String).trim();
          expect(errSec, contains('@path=${err.path}'), reason: stdout);
          expect(errSec, contains('@stat=$owner $group 640'), reason: stdout);
          expect(accSec, contains('@path=${acc.path}'), reason: stdout);
          expect(accSec.where((l) => l.startsWith('@stat')), isEmpty,
              reason: stdout);
          if (isRoot) {
            // nobody cannot read either log, with or without sudo -n.
            expect(errSec, contains('@read=fail'), reason: stdout);
            expect(accSec, contains('@read=fail'), reason: stdout);
          }
          final groups = section(stdout, 'TOOLS')
              .where((l) => l.startsWith('@groups='))
              .toList();
          expect(groups, hasLength(1), reason: stdout);
          final lens = parseWebLens(stdout, id: ServiceId.nginx, now: now);
          expect(lens.errorLogStat?.group, group);
          expect(lens.errorLogStat?.groupReadable, isTrue);
          expect(lens.accessLogStat, isNull);
          expect(lens.loginGroups, isNotEmpty);
          if (isRoot) {
            expect(lens.loginGroups, isNot(contains('adm')));
            expect(lens.sectionErrors[WebLensSection.errorLog], isNotNull);
          }
        }, skip: Platform.isWindows);
      }
    });

    test('host-derived values are whitelisted and quoted', () {
      final evil = const WebLensProbe(
        id: ServiceId.nginx,
        binaries: {'nginx': "/usr/sbin/nginx';reboot;'"},
        unit: "nginx.service; reboot",
      ).command(ubuntu);
      expect(evil, isNot(contains('reboot')));
      expect(evil, contains("B='nginx'"));
      expect(evil, isNot(contains('systemctl is-active')));
      // A safe path whose last segment is not the binary is refused too.
      final shell = const WebLensProbe(
        id: ServiceId.nginx,
        binaries: {'nginx': '/bin/sh'},
      ).command(ubuntu);
      expect(shell, isNot(contains('/bin/sh')));
      final openrc =
          const WebLensProbe(
            id: ServiceId.nginx,
            binaries: {},
            unit: 'nginx',
          ).command(
            const HostFacts(
              osId: 'alpine',
              osVersionId: '3.20',
              init: InitSystem.openrc,
              systemdVersion: null,
              pkg: PackageManager.apk,
              fw: FirewallBackend.none,
              hasJournald: false,
              journalReadable: false,
              arch: 'x86_64',
            ),
          );
      expect(openrc, contains("rc-service 'nginx' status"));
    });

    test('sbin dirs are appended to PATH before any command -v', () {
      const line = r'PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"; export PATH';
      for (final p in [nginx, apache]) {
        for (final f in [ubuntu, rocky]) {
          final cmd = p.command(f);
          expect(cmd.split('\n').first, line);
          expect(cmd.indexOf(line), lessThan(cmd.indexOf('command -v')));
        }
      }
    });

    test('tools only in an sbin dir are found (executed)', () async {
      final dir = await Directory.systemTemp.createTemp('kelola_lens_sbin');
      addTearDown(() => dir.delete(recursive: true));
      File('${dir.path}/openssl').writeAsStringSync('#!/bin/sh\nexit 1\n');
      await Process.run('chmod', ['+x', '${dir.path}/openssl']);
      final cmd = const WebLensProbe(
        id: ServiceId.nginx,
        binaries: {},
      ).command(ubuntu).replaceFirst(
        ':/usr/local/sbin:/usr/sbin:/sbin"',
        ':${dir.path}"',
      );
      final r = await Process.run(
        '/bin/sh',
        ['-c', cmd],
        // No openssl on the login PATH: only the appended dir has one.
        environment: {'PATH': '/nonexistent'},
      );
      expect(r.stdout, contains('|openssl ${dir.path}/openssl'));
    }, skip: Platform.isWindows);

    group('sudo refusal wording in the config test (executed)', () {
      for (final msg in [
        'sudo: sorry, you must have a tty to run sudo',
        'sudo-rs: interactive authentication is required',
        "sudo-rs: I'm sorry deploy. I'm afraid I can't do that",
      ]) {
        test(msg, () async {
          final dir = await Directory.systemTemp.createTemp('kelola_tty');
          addTearDown(() => dir.delete(recursive: true));
          Future<void> stub(String name, String body) async {
            File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
            await Process.run('chmod', ['+x', '${dir.path}/$name']);
          }

          await stub('sudo', "echo '${msg.replaceAll("'", r"'\''")}' >&2\nexit 1");
          await stub(
            'nginx',
            'echo "nginx: [alert] could not open error log file: open() '
                '\\"/var/log/nginx/error.log\\" failed (13: Permission denied)" >&2\n'
                'exit 1',
          );
          final probe = WebLensProbe(
            id: ServiceId.nginx,
            binaries: {'nginx': '${dir.path}/nginx'},
          );
          final r = await Process.run(
            'sh',
            ['-c', probe.command(ubuntu)],
            environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
          );
          expect(r.stdout, contains('---CONFTEST---\n@rc=nosudo\n'));
          // Never a failed config test: sudo was refused.
          expect(
            () => parseWebLens(r.stdout as String, id: ServiceId.nginx, now: now),
            throwsA(isA<SudoRequiredException>()),
          );
        }, skip: Platform.isWindows);
      }
    });

    group('Apache certificates come from the enabled config only (executed)', () {
      late Directory dir;
      late Directory conf;
      late File log;

      Future<void> stub(String name, String body) async {
        File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
        await Process.run('chmod', ['+x', '${dir.path}/$name']);
      }

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('kelola_apache_certs');
        conf = Directory('${dir.path}/apache2')..createSync();
        log = File('${dir.path}/openssl.log');
        await stub('apache2ctl', '''
case "\$1" in
  -t) echo "Syntax OK" >&2 ;;
  -S) cat <<'DUMP'
VirtualHost configuration:
*:443                  site.example (${conf.path}/sites-enabled/site.conf:2)
DUMP
  ;;
esac''');
        await stub('openssl', '''
echo "\$*" >> ${log.path}
echo "notAfter=Nov 15 01:32:00 2030 GMT"
echo "subject=CN = site.example"''');
        await stub('tail', 'exit 0');
      });

      tearDown(() => dir.delete(recursive: true));

      void write(String rel, String text) {
        final f = File('${conf.path}/$rel')..createSync(recursive: true);
        f.writeAsStringSync(text);
      }

      Future<(ProcessResult, WebLens)> run() async {
        final probe = WebLensProbe(
          id: ServiceId.apache,
          binaries: {'apache2ctl': '${dir.path}/apache2ctl'},
        );
        final cmd = probe.command(ubuntu);
        // Production always reads apacheConfigDir(facts); the test points
        // that one assignment at the temp tree.
        expect("D='/etc/apache2'".allMatches(cmd), hasLength(1));
        final r = await Process.run(
          'sh',
          ['-c', cmd.replaceFirst("D='/etc/apache2'", "D='${conf.path}'")],
          environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
        );
        return (
          r,
          parseWebLens(r.stdout as String, id: ServiceId.apache, now: now),
        );
      }

      List<String> calls() => log.existsSync() ? log.readAsLinesSync() : [];

      test('disabled sites are not read; enabled symlinks are followed', () async {
        write('apache2.conf', 'IncludeOptional sites-enabled/*.conf\n');
        write(
          'sites-available/site.conf',
          '<VirtualHost *:443>\n'
              '  SSLCertificateFile /etc/ssl/site.pem\n'
              '  SSLCertificateKeyFile /etc/ssl/private/site.key\n'
              '</VirtualHost>\n',
        );
        write(
          'sites-available/disabled.conf',
          '<VirtualHost *:443>\n  SSLCertificateFile /etc/ssl/old.pem\n</VirtualHost>\n',
        );
        Directory('${conf.path}/sites-enabled').createSync();
        Link('${conf.path}/sites-enabled/site.conf')
            .createSync('../sites-available/site.conf');
        write('mods-available/ssl.conf', 'SSLCertificateFile /etc/ssl/mod.pem\n');
        Directory('${conf.path}/mods-enabled').createSync();
        Link('${conf.path}/mods-enabled/ssl.conf')
            .createSync('${conf.path}/mods-available/ssl.conf');
        write('mods-enabled/ssl.load', 'SSLCertificateFile /etc/ssl/load.pem\n');
        write(
          'conf-enabled/x.conf',
          '#SSLCertificateFile /etc/ssl/commented.pem\n',
        );
        final (r, lens) = await run();
        expect(calls(), [
          'x509 -noout -enddate -subject -ext subjectAltName -in /etc/ssl/site.pem',
          'x509 -noout -enddate -subject -ext subjectAltName -in /etc/ssl/mod.pem',
        ], reason: '${r.stdout}');
        expect(lens.certsByPath.keys, ['/etc/ssl/site.pem', '/etc/ssl/mod.pem']);
        expect(lens.sectionErrors[WebLensSection.certs], isNull);
        expect(r.stdout, isNot(contains('.key')));
      }, skip: Platform.isWindows);

      test('a missing config dir is a cert section error, not 443 without cert', () async {
        conf.deleteSync(recursive: true);
        final (_, lens) = await run();
        expect(calls(), isEmpty);
        expect(
          lens.sectionErrors[WebLensSection.certs],
          'Could not read the Apache httpd config for certificates',
        );
        expect(lens.vhosts.single.listen.single, '*:443');
        expect(
          lens.findings.where(
            (f) => f.kind == WebFindingKind.listens443WithoutCert,
          ),
          isEmpty,
        );
      }, skip: Platform.isWindows);
    });

    test('shell cert loop passes only ssl_certificate paths to openssl (executed)', () async {
      final dir = await Directory.systemTemp.createTemp('kelola_weblens');
      addTearDown(() => dir.delete(recursive: true));
      final log = File('${dir.path}/openssl.log');
      final dump = [
        '# configuration file /etc/nginx/nginx.conf:',
        'http {',
        '  server {',
        '    listen 443 ssl;',
        '    ssl_certificate /etc/ssl/a.pem;',
        '    ssl_certificate_key /etc/ssl/private/a.key;',
        '    ssl_certificate "/etc/ssl/b.pem";',
        '    ssl_certificate /etc/ssl/a.pem;',
        '    # ssl_certificate /etc/ssl/commented.pem;',
        r'    ssl_certificate /etc/ssl/$ssl_server_name.pem;',
        '    ssl_certificate /etc/ssl/../shadow;',
        '    ssl_certificate relative.pem;',
        '    ssl_certificate_key /etc/ssl/private/b.key;',
        '  }',
        '}',
        'error_log /var/log/x/err.log warn;',
        'access_log /var/log/x/acc.log combined;',
      ].join('\n');
      File('${dir.path}/nginx').writeAsStringSync(
        '#!/bin/sh\n'
        'if [ "\$1" = -T ]; then cat <<\'EOF\'\n$dump\nEOF\n'
        'else echo "nginx: test is successful" >&2; fi\n',
      );
      File('${dir.path}/openssl').writeAsStringSync(
        '#!/bin/sh\n'
        'echo "\$*" >> ${log.path}\n'
        'echo "notAfter=Nov 15 01:32:00 2026 GMT"\n'
        'echo "subject=CN = x"\n',
      );
      File('${dir.path}/tail')
          .writeAsStringSync('#!/bin/sh\necho "\$*" >> ${dir.path}/tail.log\n');
      for (final f in ['nginx', 'openssl', 'tail']) {
        await Process.run('chmod', ['+x', '${dir.path}/$f']);
      }
      final probe = WebLensProbe(
        id: ServiceId.nginx,
        binaries: {'nginx': '${dir.path}/nginx'},
      );
      final r = await Process.run(
        'sh',
        ['-c', probe.command(ubuntu)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      final calls = log.readAsLinesSync();
      expect(calls, [
        'x509 -noout -enddate -subject -ext subjectAltName -in /etc/ssl/a.pem',
        'x509 -noout -enddate -subject -ext subjectAltName -in /etc/ssl/b.pem',
      ]);
      expect(File('${dir.path}/tail.log').readAsLinesSync(), [
        '-n 60 /var/log/x/err.log',
        '-n 2000 /var/log/x/acc.log',
      ]);
      final lens = parseWebLens(
        r.stdout as String,
        id: ServiceId.nginx,
        now: now,
      );
      expect(lens.certsByPath.keys, ['/etc/ssl/a.pem', '/etc/ssl/b.pem']);
      expect(lens.configOk, isTrue);
      expect(lens.vhosts, hasLength(1));
      expect(lens.errorLogPath, '/var/log/x/err.log');
      expect(lens.accessLogPath, '/var/log/x/acc.log');
      expect(lens.toolPaths['openssl'], '${dir.path}/openssl');
    }, skip: Platform.isWindows);
  });
}
