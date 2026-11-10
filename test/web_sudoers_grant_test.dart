import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/config_tested_reload_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/sudo_hint.dart';

const _nginxBins = {'nginx': '/usr/sbin/nginx'};
const _tools = {'openssl': '/usr/bin/openssl', 'tail': '/usr/bin/tail'};
const _prefix = 'hendr ALL=(root) NOPASSWD: ';

List<String> _nginxLines({
  Map<String, String> binaries = _nginxBins,
  Map<String, String> toolPaths = _tools,
  List<String> certPaths = const [
    '/etc/letsencrypt/live/example.com/fullchain.pem',
  ],
  String? errorLog = '/var/log/nginx/error.log',
  String? accessLog = '/var/log/nginx/access.log',
}) => webGrantLines(
  user: 'hendr',
  id: ServiceId.nginx,
  binaries: binaries,
  toolPaths: toolPaths,
  certPaths: certPaths,
  errorLog: errorLog,
  accessLog: accessLog,
);

HostFacts _ubuntu() => const HostFacts(
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

/// Every character sudoers treats specially in a command, plus the path
/// tricks spec §7b refuses.
const _unsafePaths = [
  '/etc/ssl/a b.pem',
  '/etc/ssl/a,b.pem',
  '/etc/ssl/a:b.pem',
  '/etc/ssl/a=b.pem',
  r'/etc/ssl/a\b.pem',
  '/etc/ssl/*.pem',
  '/etc/ssl/a?.pem',
  '/etc/ssl/[a].pem',
  '/etc/ssl/a].pem',
  '/etc/ssl/!a.pem',
  '/etc/ssl/a#b.pem',
  '/etc/ssl/a\tb.pem',
  '/etc/ssl/a\nhendr ALL=(ALL) NOPASSWD: ALL',
  '/etc/ssl/../shadow',
  '/etc/ssl/..',
  '/etc//shadow',
  'etc/ssl/a.pem',
  '',
  '/etc/ssl/a.pem -out /etc/passwd',
  '/etc/ssl/\$(id).pem',
  '/etc/ssl/a"b.pem',
  "/etc/ssl/a'b.pem",
  '/etc/ssl/^a.pem',
];

void main() {
  group('lines', () {
    test('lines use detected absolute paths', () {
      expect(_nginxLines(), [
        '$_prefix/usr/sbin/nginx -t',
        '$_prefix/usr/sbin/nginx -T',
        '$_prefix/usr/bin/openssl x509 -noout -enddate -subject -ext '
            'subjectAltName -in /etc/letsencrypt/live/example.com/fullchain.pem',
        '$_prefix/usr/bin/tail -n 60 /var/log/nginx/error.log',
        '$_prefix/usr/bin/tail -n 2000 /var/log/nginx/access.log',
      ]);
      expect(
        webGrantLines(
          user: 'hendr',
          id: ServiceId.apache,
          binaries: const {
            'apache2': '/usr/sbin/apache2',
            'apache2ctl': '/usr/sbin/apache2ctl',
          },
          toolPaths: const {'openssl': '/bin/openssl', 'tail': '/bin/tail'},
          errorLog: '/var/log/apache2/error.log',
          accessLog: '/var/log/apache2/access.log',
        ),
        [
          '$_prefix/usr/sbin/apache2ctl -t',
          '$_prefix/usr/sbin/apache2ctl -S',
          '$_prefix/bin/tail -n 60 /var/log/apache2/error.log',
          '$_prefix/bin/tail -n 2000 /var/log/apache2/access.log',
        ],
      );
    });

    test('the server binary is the one the probes run', () {
      const binaries = {
        'httpd': '/usr/sbin/httpd',
        'apachectl': '/usr/sbin/apachectl',
      };
      final picked = safeWebBinary(
        binaries,
        webConfigTestBinaryNames(ServiceId.apache),
      );
      expect(picked, '/usr/sbin/apachectl');
      final lines = webGrantLines(
        user: 'hendr',
        id: ServiceId.apache,
        binaries: binaries,
      );
      expect(lines, [
        '$_prefix/usr/sbin/apachectl -t',
        '$_prefix/usr/sbin/apachectl -S',
      ]);
      // The probes run the first safe binary; when that one may not be
      // granted, no other binary stands in for it.
      final none = webGrantLines(
        user: 'hendr',
        id: ServiceId.apache,
        binaries: const {
          'apachectl': '/opt/apache/bin/apachectl',
          'apache2ctl': '/usr/sbin/apache2ctl',
        },
      );
      expect(none, isEmpty);
    });

    test('a binary outside a root-owned system directory gets no line', () {
      for (final path in [
        'nginx',
        'sbin/nginx',
        '/home/hendr/bin/nginx',
        '/tmp/nginx',
        '/opt/nginx/sbin/nginx',
        '/usr/local/nginx/sbin/nginx',
        '/usr/local/bin/nginx',
        '/usr/local/sbin/nginx',
        '/usr/sbin/../../tmp/nginx',
        '/usr/sbin/./nginx',
        '/usr//sbin/nginx',
        '/usr/sbin/nginx-debug',
        '/usr/sbin/sub/nginx',
        '/var/tmp/nginx',
        '/nginx',
        '/usr/sbin/',
      ]) {
        final lines = _nginxLines(binaries: {'nginx': path});
        expect(
          lines.where((l) => l.endsWith(' -t') || l.endsWith(' -T')),
          isEmpty,
          reason: path,
        );
        expect(isGrantableWebBinary(path, 'nginx'), isFalse, reason: path);
      }
      for (final dir in webGrantSystemDirs) {
        expect(isGrantableWebBinary('$dir/nginx', 'nginx'), isTrue);
      }
      expect(webGrantSystemDirs, {'/usr/bin', '/usr/sbin', '/bin', '/sbin'});
    });

    test('tools outside a system directory, or misnamed, get no line', () {
      for (final tools in [
        {'openssl': '/home/hendr/openssl', 'tail': '/tmp/tail'},
        {'openssl': 'openssl', 'tail': 'tail'},
        {'openssl': '/usr/bin/tail', 'tail': '/usr/bin/openssl'},
        {'openssl': '/opt/ssl/bin/openssl', 'tail': '/usr/bin/../../tmp/tail'},
        {'openssl': '/usr/local/bin/openssl', 'tail': '/usr/local/bin/tail'},
        {'openssl': '/usr/local/sbin/openssl', 'tail': '/usr/local/sbin/tail'},
        <String, String>{},
      ]) {
        final lines = _nginxLines(toolPaths: tools);
        expect(lines, [
          '$_prefix/usr/sbin/nginx -t',
          '$_prefix/usr/sbin/nginx -T',
        ], reason: '$tools');
      }
    });

    test('one openssl line per safe cert path; none for a path with space, comma, colon or ..', () {
      final lines = _nginxLines(
        certPaths: [
          '/etc/ssl/certs/a.pem',
          '/etc/ssl/certs/b+c@d_e-f.pem',
          '/etc/ssl/certs/a.pem',
          ..._unsafePaths,
        ],
        errorLog: null,
        accessLog: null,
      );
      final openssl = lines.where((l) => l.contains(' x509 ')).toList();
      expect(openssl, [
        '$_prefix/usr/bin/openssl x509 -noout -enddate -subject -ext '
            'subjectAltName -in /etc/ssl/certs/a.pem',
        '$_prefix/usr/bin/openssl x509 -noout -enddate -subject -ext '
            'subjectAltName -in /etc/ssl/certs/b+c@d_e-f.pem',
      ]);
      for (final p in _unsafePaths) {
        expect(isGrantableWebPath(p), isFalse, reason: p);
        final logs = _nginxLines(
          certPaths: const [],
          errorLog: p,
          accessLog: p,
        );
        expect(
          logs.where((l) => l.contains(' tail ') || l.contains('/tail')),
          isEmpty,
          reason: p,
        );
      }
    });

    test('no line contains *, ^ or starts with !', () {
      final inputs = [
        _nginxLines(),
        _nginxLines(certPaths: _unsafePaths, errorLog: '/x*', accessLog: '!/x'),
        _nginxLines(
          binaries: const {'nginx': '/usr/sbin/nginx*'},
          toolPaths: const {
            'openssl': '/usr/bin/openssl ^',
            'tail': '!/usr/bin/tail',
          },
        ),
        webGrantLines(
          user: 'hendr',
          id: ServiceId.apache,
          binaries: const {'apachectl': '/usr/sbin/apachectl'},
          toolPaths: _tools,
          certPaths: const ['/etc/pki/tls/certs/localhost.crt', '/etc/x/*'],
          errorLog: '/var/log/httpd/error_log',
          accessLog: '/var/log/httpd/access_log',
        ),
      ];
      for (final lines in inputs) {
        for (final line in lines) {
          expect(line, startsWith(_prefix));
          final cmd = line.substring(_prefix.length);
          expect(cmd, isNot(contains('*')), reason: line);
          expect(cmd, isNot(contains('^')), reason: line);
          expect(cmd, isNot(contains(r'$')), reason: line);
          expect(cmd, isNot(contains('?')), reason: line);
          expect(cmd, isNot(contains('[')), reason: line);
          expect(cmd, isNot(contains('!')), reason: line);
          expect(cmd, isNot(contains('"')), reason: line);
          expect(line, isNot(startsWith('!')));
          expect(line, isNot(contains('Cmnd_Alias')));
          expect(line, isNot(contains('\n')));
          // Every rule names its arguments, never "any arguments".
          expect(cmd.split(' ').length, greaterThan(1), reason: line);
        }
      }
    });

    test('lines identical for classic and sudo-rs', () {
      // No flavor goes in, so no flavor can change a line; and nothing in a
      // line means something different to classic sudo and sudo-rs (no
      // regex, no wildcard, no escapes).
      final src = File('lib/domain/sudo/web_sudoers_grant.dart')
          .readAsStringSync();
      expect(src, isNot(contains('SudoFlavor')));
      expect(src, isNot(contains('supportsArgRegex')));
      for (final line in _nginxLines()) {
        expect(
          RegExp(r'[*?\[\]^$\\!,:=]').hasMatch(line.substring(_prefix.length)),
          isFalse,
          reason: line,
        );
      }
    });

    test('an unsafe user name gives no lines and no grant', () {
      for (final user in [
        '',
        'a b',
        'ALL,',
        '%sudo',
        'a\nb',
        '#0',
        'root ALL',
        'ALL',
        'all',
        'All',
        'aLl',
      ]) {
        final lines = webGrantLines(
          user: user,
          id: ServiceId.nginx,
          binaries: _nginxBins,
          toolPaths: _tools,
        );
        expect(lines, isEmpty, reason: user);
        expect(
          WebSudoersGrant.tryCreate(
            user: user,
            id: ServiceId.nginx,
            binaries: _nginxBins,
          ),
          isNull,
          reason: user,
        );
      }
    });

    test('only nginx and Apache have lens lines', () {
      for (final id in ServiceId.values) {
        final lines = webGrantLines(
          user: 'hendr',
          id: id,
          binaries: const {
            'nginx': '/usr/sbin/nginx',
            'apachectl': '/usr/sbin/apachectl',
            'mysqld': '/usr/sbin/mysqld',
          },
        );
        expect(
          lines.isNotEmpty,
          id == ServiceId.nginx || id == ServiceId.apache,
          reason: id.name,
        );
      }
    });

    test('each cert and log line names the one path it depends on', () {
      final g = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: _nginxBins,
        toolPaths: _tools,
        certPaths: const ['/etc/ssl/certs/a.pem', '/etc/ssl/a b.pem'],
        errorLog: '/var/log/nginx/error.log',
        accessLog: '/var/log/nginx/access.log',
      )!;
      expect(g.lines, hasLength(5));
      expect(g.linePaths, [
        null,
        null,
        '/etc/ssl/certs/a.pem',
        '/var/log/nginx/error.log',
        '/var/log/nginx/access.log',
      ]);
      for (var i = 0; i < g.lines.length; i++) {
        final p = g.linePaths[i];
        if (p != null) expect(g.lines[i], endsWith(' $p'));
      }
      // The same file as error and access log: two lines, one path.
      final same = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: const {},
        toolPaths: _tools,
        errorLog: '/var/log/nginx/all.log',
        accessLog: '/var/log/nginx/all.log',
      )!;
      expect(same.linePaths, ['/var/log/nginx/all.log', '/var/log/nginx/all.log']);
    });

    test('the grant is null without lines', () {
      expect(
        WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.nginx,
          binaries: const {'nginx': '/opt/nginx/sbin/nginx'},
          toolPaths: const {'tail': '/opt/bin/tail'},
          errorLog: '/var/log/nginx/error.log',
        ),
        isNull,
      );
      final g = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: _nginxBins,
      )!;
      expect(g.id, ServiceId.nginx);
      expect(g.user, 'hendr');
      expect(g.lines, hasLength(2));
    });
  });

  group('lines match the probes', () {
    late Directory dir;
    late File log;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kelola_web_grant');
      log = File('${dir.path}/sudo.log');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> stub(String name, String body) async {
      File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', '${dir.path}/$name']);
    }

    test('every granted line is the argv the lens probe runs under sudo -n', () async {
      // Each tool fails unless run through the sudo stub, so every read goes
      // through `sudo -n`, and the stub logs the exact argv.
      const gate =
          '[ "\$KELOLA_ROOT" = 1 ] || { echo "Permission denied" >&2; exit 1; }';
      await stub(
        'sudo',
        '[ "\$1" = -n ] || exit 9\nshift\n'
            "printf '%s\\n' \"\$*\" >> ${log.path}\n"
            'KELOLA_ROOT=1 exec "\$@"',
      );
      await stub('nginx', '''
$gate
case "\$1" in
  -t) echo "nginx: configuration file /etc/nginx/nginx.conf test is successful" >&2 ;;
  -T) cat <<'CONF'
server {
    listen 443 ssl;
    server_name shop.example.com;
    ssl_certificate /etc/ssl/certs/shop.pem;
    ssl_certificate_key /etc/ssl/private/shop.key;
    ssl_certificate "/etc/ssl/certs/odd name.pem";
    error_log /var/log/nginx/shop-error.log;
    access_log /var/log/nginx/shop-access.log;
}
CONF
  ;;
esac''');
      await stub('openssl', '''
$gate
echo "notAfter=Dec  1 08:30:00 2030 GMT"
echo "subject=CN = shop.example.com"''');
      await stub('tail', '$gate\necho "x"');
      await stub('systemctl', 'echo active');

      final probe = WebLensProbe(
        id: ServiceId.nginx,
        binaries: {'nginx': '${dir.path}/nginx'},
        unit: 'nginx.service',
      );
      final r = await Process.run(
        'sh',
        ['-c', probe.command(_ubuntu())],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      final lens = probe.parse(
        r.stdout as String,
        r.stderr as String,
        r.exitCode,
      );
      expect(lens.toolPaths['openssl'], '${dir.path}/openssl');
      expect(lens.certsByPath.keys, ['/etc/ssl/certs/shop.pem']);

      // The stubs live in a temp dir, which may never be granted; grant the
      // same lens as if they sat in /usr/sbin and /usr/bin.
      final sys = {
        '${dir.path}/nginx': '/usr/sbin/nginx',
        '${dir.path}/openssl': '/usr/bin/openssl',
        '${dir.path}/tail': '/usr/bin/tail',
      };
      final granted = webGrantLines(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: const {'nginx': '/usr/sbin/nginx'},
        toolPaths: {
          for (final e in lens.toolPaths.entries) e.key: sys[e.value]!,
        },
        certPaths: lens.certsByPath.keys.toList(),
        errorLog: lens.errorLogPath,
        accessLog: lens.accessLogPath,
      ).map((l) => l.substring(_prefix.length)).toList();

      final ran = log.readAsLinesSync().map((l) {
        final bin = l.split(' ').first;
        return '${sys[bin] ?? bin}${l.substring(bin.length)}';
      }).toList();
      expect(ran.toSet(), granted.toSet());
      expect(granted, [
        '/usr/sbin/nginx -t',
        '/usr/sbin/nginx -T',
        '/usr/bin/openssl x509 -noout -enddate -subject -ext subjectAltName '
            '-in /etc/ssl/certs/shop.pem',
        '/usr/bin/tail -n 60 /var/log/nginx/shop-error.log',
        '/usr/bin/tail -n 2000 /var/log/nginx/shop-access.log',
      ]);

      // The reload probe's config test runs the same `-t` line.
      log.deleteSync();
      final reload = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '${dir.path}/nginx',
      );
      await stub(
        'sudo',
        '[ "\$1" = -n ] || exit 9\nshift\n'
            "printf '%s\\n' \"\$*\" >> ${log.path}\n"
            '[ "\$1" = systemctl ] && exit 0\n'
            'KELOLA_ROOT=1 exec "\$@"',
      );
      await Process.run(
        'sh',
        ['-c', reload.command(_ubuntu())],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      final test = log.readAsLinesSync().first;
      expect(
        '${sys[test.split(' ').first]} ${test.split(' ').skip(1).join(' ')}',
        granted.first,
      );
    }, skip: Platform.isWindows);
  });

  group('install script', () {
    WebSudoersGrant grant() => WebSudoersGrant.tryCreate(
      user: 'hendr',
      id: ServiceId.nginx,
      binaries: _nginxBins,
      toolPaths: _tools,
      certPaths: const ['/etc/ssl/certs/a.pem'],
      errorLog: '/var/log/nginx/error.log',
      accessLog: '/var/log/nginx/access.log',
    )!;

    test('script keeps existing lines, adds missing only, runs visudo -c -f before install', () {
      final script = buildWebGrantScript(grant());
      expect(script, contains('IFS= read -r SUDO_PASS'));
      expect(script, contains('unset SUDO_PASS'));
      expect(script, contains("'$kelolaWebSudoersPath'"));
      expect(script, isNot(contains("'$kelolaSudoersPath'")));
      expect(script, isNot(contains("'$kelolaUnitSudoersPath'")));
      expect(kelolaWebSudoersPath.split('/').last, 'kelola-web');
      expect(
        script.indexOf('visudo -c -f'),
        lessThan(script.indexOf(' install -o root')),
      );
      expect(
        script,
        contains(
          '# Kelola: lens read rules, one command per line. Safe to edit.',
        ),
      );
      expect(script, contains(webGrantOkMarker));
      expect(webGrantOkMarker, isNot(unitGrantOkMarker));
      // The binaries are checked before anything is read or written.
      final trust = script.indexOf('kelola_trust "');
      expect(trust, greaterThan(0));
      expect(trust, lessThan(script.indexOf('test -f')));
      expect(trust, lessThan(script.indexOf('visudo -c -f')));
      expect(trust, lessThan(script.indexOf(' install -o root')));
      for (final b in [
        '/usr/sbin/nginx',
        '/usr/bin/openssl',
        '/usr/bin/tail',
      ]) {
        expect(
          'kelola_trust "\$(printf \'%s\' \'${base64Encode(utf8.encode(b))}\' | base64 -d)"'
              .allMatches(script)
              .length,
          1,
          reason: b,
        );
      }
      // Portable find only (busybox has no -perm /mode).
      expect(script, isNot(contains('-perm /')));
      expect(script, contains('! -perm -020 ! -perm -002'));
      // The unit script has no trust check (it stays byte-identical).
      expect(
        buildUnitGrantScript(
          UnitSudoersGrant.tryCreate(
            user: 'hendr',
            verb: 'reload',
            unit: 'nginx.service',
          )!,
        ),
        isNot(contains('kelola_trust')),
      );
      for (final line in grant().lines) {
        // Carried encoded, never raw.
        expect(script, contains(base64Encode(utf8.encode(line))));
        expect(script, isNot(contains(line)));
      }
    });

    test('each cert and log path is walked before anything is read, and gates only its own line', () {
      final g = grant();
      final script = buildWebGrantScript(g);
      final firstRead = script.indexOf('test -f');
      final paths = [for (final p in g.linePaths) ?p];
      expect(paths, hasLength(3));
      for (var j = 0; j < paths.length; j++) {
        final b64 = base64Encode(utf8.encode(paths[j]));
        final walk = script.indexOf(
          'if kelola_walk "\$(printf \'%s\' \'$b64\' | base64 -d)" path; '
          'then KELOLA_P$j=1; else '
          "printf '%s %s\\n' '$webGrantSkippedMarker' '$b64'; fi",
        );
        expect(walk, greaterThan(0), reason: paths[j]);
        expect(walk, lessThan(firstRead), reason: paths[j]);
        // Carried encoded only.
        expect(script, isNot(contains(paths[j])));
      }
      for (var i = 0; i < g.lines.length; i++) {
        final v = i == 0 ? 'LINE' : 'LINE$i';
        final p = g.linePaths[i];
        final merge = 'grep -qxF -- "\$$v" "\$TMP" || '
            "printf '%s\\n' \"\$$v\" >> \"\$TMP\"";
        if (p == null) {
          // The server binary's config test lines: gated by the config
          // trust check (fix 1), never always-on.
          expect(script, isNot(contains('\n$merge\n')), reason: v);
          expect(
            script,
            contains('if [ "\$KELOLA_CFG" = 1 ]; then $merge; fi'),
            reason: v,
          );
        } else {
          final j = paths.indexOf(p);
          expect(
            script,
            contains('if [ "\$KELOLA_P$j" = 1 ]; then $merge; fi'),
            reason: v,
          );
          expect(
            script,
            contains(
              'if [ "\$KELOLA_P$j" = 1 ]; then printf \'%s\\n\' '
              '"\$SUDO_PASS" | sudo -S -p \'\' grep -qxF -- "\$$v" ',
            ),
            reason: v,
          );
        }
      }
      // Every line is gated now, so all dropped stops before sudo, with the
      // config test counted like a path.
      final all = script.indexOf(
        '[ "\$KELOLA_P0" = 1 ] || [ "\$KELOLA_P1" = 1 ] || '
        '[ "\$KELOLA_P2" = 1 ] || [ "\$KELOLA_CFG" = 1 ] || exit 6',
      );
      expect(all, greaterThan(0));
      expect(all, lessThan(firstRead));
      final logsOnly = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: const {},
        toolPaths: _tools,
        errorLog: '/var/log/nginx/error.log',
        accessLog: '/var/log/nginx/access.log',
      )!;
      final s2 = buildWebGrantScript(logsOnly);
      final stop = s2.indexOf(
        '[ "\$KELOLA_P0" = 1 ] || [ "\$KELOLA_P1" = 1 ] || exit 6',
      );
      expect(stop, greaterThan(0));
      expect(stop, lessThan(s2.indexOf('test -f')));
      // No config test line, no config check.
      expect(s2, isNot(contains('kelola_cfg')));
      expect(s2, isNot(contains('KELOLA_CFG')));
    });

    test('the config trust check runs before anything is read, as the login, and gates only the config test lines', () {
      for (final g in [
        grant(),
        WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.apache,
          binaries: const {'apachectl': '/usr/sbin/apachectl'},
          toolPaths: _tools,
          certPaths: const ['/etc/ssl/certs/a.pem'],
          configFiles: const ['/etc/apache2/sites-enabled/shop.conf'],
        )!,
      ]) {
        final script = buildWebGrantScript(g);
        final firstRead = script.indexOf('test -f');
        final gate = script.indexOf('if kelola_cfg; then KELOLA_CFG=1; else');
        expect(gate, greaterThan(0));
        expect(gate, lessThan(firstRead));
        // After the binaries passed their own check.
        expect(gate, greaterThan(script.lastIndexOf('kelola_trust "')));
        // No sudo inside the check: the first sudo is the read.
        expect(script.indexOf('sudo '), greaterThan(gate));
        expect(script, contains("'$webGrantConfigMarker'"));
        // Production: no test prefix, real locations only.
        expect(script, contains('\nkelola_pre=\n'));
        expect(script, contains('kelola_cap=$webConfigTrustMaxEntries\n'));
        expect(webConfigTrustMaxEntries, 2000);
        // Portable find only.
        expect(script, isNot(contains('-perm /')));
        expect(script, isNot(contains('readlink -f')));
        expect(script, isNot(contains('-readable')));
        expect(script, isNot(contains('-printf')));
        for (var i = 0; i < g.lines.length; i++) {
          if (g.linePaths[i] != null) continue;
          final v = i == 0 ? 'LINE' : 'LINE$i';
          expect(
            script,
            contains(
              'if [ "\$KELOLA_CFG" = 1 ]; then printf \'%s\\n\' '
              '"\$SUDO_PASS" | sudo -S -p \'\' grep -qxF -- "\$$v" ',
            ),
          );
        }
      }
      // Apache: its config roots, envvars and module directories; nginx:
      // the -V conf path and its own module directories.
      final apache = buildWebGrantScript(
        WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.apache,
          binaries: const {'apachectl': '/usr/sbin/apachectl'},
        )!,
      );
      for (final p in [
        '/etc/apache2',
        '/etc/httpd',
        '/etc/apache2/envvars',
        '/usr/lib/apache2/modules',
        '/usr/lib64/httpd/modules',
      ]) {
        expect(apache, contains('"\$kelola_pre$p"'), reason: p);
      }
      expect(apache, isNot(contains(' -V ')));
      final nginx = buildWebGrantScript(grant());
      for (final p in [
        '/etc/nginx',
        '/usr/lib/nginx/modules',
        '/usr/lib64/nginx/modules',
      ]) {
        expect(nginx, contains('\$kelola_pre$p'), reason: p);
      }
      expect(nginx, contains('"\$kelola_pre"/usr/share/nginx/modules*'));
      expect(nginx, contains('"\$kelola_bin" -V'));
      expect(nginx, isNot(contains('/etc/apache2')));
    });

    test('dump-named config files travel encoded; an unsafe one or too many fail closed', () {
      final files = [
        '/etc/nginx/nginx.conf',
        '/etc/letsencrypt/options-ssl-nginx.conf',
      ];
      WebSudoersGrant g(List<String> f) => WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: _nginxBins,
        configFiles: f,
      )!;
      final script = buildWebGrantScript(g(files));
      for (final f in files) {
        expect(script, contains("'${base64Encode(utf8.encode(f))}'"));
        expect(script, isNot(contains(f)));
      }
      // A path the check cannot quote safely: untrusted, never skipped.
      final odd = buildWebGrantScript(g(['/etc/nginx/a b.conf']));
      expect(odd, contains('unreadable; return 1'));
      expect(odd, isNot(contains('/etc/nginx/a b.conf')));
      // Too many to check: the cap, without listing them.
      final many = buildWebGrantScript(
        g([for (var i = 0; i <= webConfigTrustMaxEntries; i++) '/etc/n/$i.conf']),
      );
      expect(many, contains('cap; return 1'));
      expect(many.length, lessThan(40000));
      // Without a config test line the files are not needed.
      final certsOnly = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: const {},
        toolPaths: _tools,
        certPaths: const ['/etc/ssl/certs/a.pem'],
        configFiles: files,
      )!;
      expect(buildWebGrantScript(certsOnly), isNot(contains('kelola_cfg')));
    });

    test('unit grant script is byte-identical to PR #17', () {
      final snap = (jsonDecode(
        File('test/fixtures/sudoers/unit_grant_script_pre_m52.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>).cast<String, String>();
      expect(snap, hasLength(12));
      snap.forEach((key, expected) {
        final parts = key.split(' ');
        final g = UnitSudoersGrant.tryCreate(
          user: 'hendr',
          verb: parts[0],
          unit: parts[1],
        )!;
        expect(buildUnitGrantScript(g), expected, reason: key);
      });
    });

    test('Enable spec output is unchanged by M52', () {
      final snap = (jsonDecode(
        File('test/fixtures/sudoers/enable_spec_pre_m52.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>).cast<String, String>();
      const flavors = <String, SudoFlavor>{
        'classic-1.9.15': ClassicSudo(1, 9, 15),
        'classic-1.9.10': ClassicSudo(1, 9, 10),
        'classic-1.9.9': ClassicSudo(1, 9, 9),
        'classic-1.8.23': ClassicSudo(1, 8, 23),
        'sudo-rs': SudoRs('0.2.13'),
        'unknown': UnknownSudo(),
      };
      HostFacts f(InitSystem init, PackageManager pkg, FirewallBackend fw) =>
          HostFacts(
            osId: 'x',
            osVersionId: '1',
            init: init,
            systemdVersion: 252,
            pkg: pkg,
            fw: fw,
            hasJournald: true,
            journalReadable: true,
            arch: 'x86_64',
          );
      String spec(HostFacts h, Set<KelolaSudoersGroup> g, SudoFlavor s) =>
          buildKelolaSudoersSpec(
            user: 'hendr',
            facts: h,
            groups: g,
            sudo: s,
          ).content;
      final now = <String, String>{};
      flavors.forEach((name, sudo) {
        for (final pkg in PackageManager.values) {
          now['packages/$name/${pkg.name}'] = spec(
            f(InitSystem.systemd, pkg, FirewallBackend.none),
            {KelolaSudoersGroup.packages},
            sudo,
          );
        }
        for (final fw in FirewallBackend.values) {
          now['firewall/$name/${fw.name}'] = spec(
            f(InitSystem.systemd, PackageManager.unknown, fw),
            {KelolaSudoersGroup.firewall},
            sudo,
          );
        }
        for (final g in [
          KelolaSudoersGroup.hostPower,
          KelolaSudoersGroup.services,
          KelolaSudoersGroup.processes,
        ]) {
          for (final init in InitSystem.values) {
            now['${g.name}/$name/${init.name}'] = spec(
              f(init, PackageManager.unknown, FirewallBackend.none),
              {g},
              sudo,
            );
          }
        }
        for (final h in [
          (
            'rocky',
            f(
              InitSystem.systemd,
              PackageManager.dnf,
              FirewallBackend.firewalld,
            ),
          ),
          (
            'ubuntu',
            f(InitSystem.systemd, PackageManager.apt, FirewallBackend.ufw),
          ),
          (
            'alpine',
            f(InitSystem.openrc, PackageManager.apk, FirewallBackend.iptables),
          ),
        ]) {
          now['all/$name/${h.$1}'] = spec(
            h.$2,
            KelolaSudoersGroup.values.toSet(),
            sudo,
          );
        }
      });
      expect(now.keys.toSet(), snap.keys.toSet());
      // Every group appears in the snapshot.
      for (final g in KelolaSudoersGroup.values) {
        expect(snap.keys.any((k) => k.startsWith('${g.name}/')), isTrue);
      }
      now.forEach((k, v) => expect(v, snap[k], reason: k));
      // No lens rule ever reaches the Enable file.
      for (final v in now.values) {
        expect(v, isNot(contains('x509')));
        expect(v, isNot(contains('kelola-web')));
      }
    });
  });

  group('install script under sh with stub sudo', () {
    late Directory dir;
    late File log;
    late File target;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('kelola_web_script');
      log = File('${dir.path}/calls.log');
      target = File('${dir.path}/kelola-web');
    });

    tearDown(() => dir.delete(recursive: true));

    Future<void> stub(String name, String body) async {
      File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
      await Process.run('chmod', ['+x', '${dir.path}/$name']);
    }

    /// sudo -S -p '': checks the password from stdin, points the sudoers path
    /// at the temp dir, logs the call and runs it.
    Future<void> sudoStub() => stub('sudo', '''
[ "\$1" = -S ] || { echo "sudo without -S" >> ${log.path}; exit 9; }
shift
[ "\$1" = -p ] || exit 9
shift 2
IFS= read -r pw
[ "\$pw" = s3cret ] || { echo "sudo: incorrect password" >&2; exit 1; }
for a; do
  shift
  [ "\$a" = $kelolaWebSudoersPath ] && a=${target.path}
  set -- "\$@" "\$a"
done
echo "sudo \$1" >> ${log.path}
exec "\$@"''');

    /// find: every binary counts as root-owned and not writable, so these
    /// tests cover the merge. The real check has its own tests.
    Future<void> trustedFind() => stub('find', 'printf "%s\\n" "\$1"');

    Future<void> installStub() => stub('install', '''
echo "install \$*" >> ${log.path}
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');

    Future<ProcessResult> run(WebSudoersGrant g) async {
      final p = await Process.start(
        'sh',
        ['-c', buildWebGrantScript(g)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      p.stdin.write('s3cret\n');
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      return ProcessResult(p.pid, await p.exitCode, out, err);
    }

    List<String> calls() => log.existsSync() ? log.readAsLinesSync() : [];

    final g = WebSudoersGrant.tryCreate(
      user: 'hendr',
      id: ServiceId.nginx,
      binaries: _nginxBins,
      toolPaths: _tools,
      certPaths: const ['/etc/ssl/certs/a.pem', '/etc/ssl/certs/b.pem'],
      errorLog: '/var/log/nginx/error.log',
      accessLog: '/var/log/nginx/access.log',
    )!;

    // For the merge tests. Only find is stubbed: the walk still needs each
    // binary and path to exist, so these name files every Linux has (no
    // nginx binary, which CI does not install). The checks have their own
    // tests on real files.
    final merge = WebSudoersGrant.tryCreate(
      user: 'hendr',
      id: ServiceId.nginx,
      binaries: const {},
      toolPaths: _tools,
      certPaths: const ['/etc/passwd', '/etc/group'],
      errorLog: '/etc/passwd',
      accessLog: '/etc/group',
    )!;

    test(
      'existing lines kept, missing added once, visudo before install',
      () async {
        await sudoStub();
        await trustedFind();
        await installStub();
        await stub('visudo', 'echo "visudo \$*" >> ${log.path}');
        const unrelated = 'hendr ALL=(root) NOPASSWD: /usr/bin/du -sh /srv';
        target.writeAsStringSync('# my notes\n$unrelated\n${merge.lines[2]}\n');

        final r = await run(merge);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, contains(webGrantOkMarker));
        final lines = target.readAsLinesSync();
        expect(lines.take(3), ['# my notes', unrelated, merge.lines[2]]);
        expect(lines.skip(3), [
          for (final l in merge.lines)
            if (l != merge.lines[2]) l,
        ]);
        final c = calls();
        final visudo = c.indexWhere((l) => l.startsWith('visudo -c -f'));
        final install = c.indexWhere(
          (l) => l.startsWith('install -o root -g root -m 0440'),
        );
        expect(visudo, greaterThanOrEqualTo(0), reason: '$c');
        expect(install, greaterThan(visudo), reason: '$c');

        // Run again: nothing is added twice.
        final again = await run(merge);
        expect(again.exitCode, 0);
        expect(target.readAsLinesSync(), lines);
      },
      skip: Platform.isWindows,
    );

    test('no file yet: header then the lines', () async {
      await sudoStub();
      await trustedFind();
      await installStub();
      await stub('visudo', 'exit 0');
      final r = await run(merge);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(target.readAsLinesSync(), [
        '# Kelola: lens read rules, one command per line. Safe to edit.',
        ...merge.lines,
      ]);
    }, skip: Platform.isWindows);

    test('an untrusted binary writes nothing', () async {
      await sudoStub();
      await installStub();
      await stub('visudo', 'echo "visudo \$*" >> ${log.path}');
      // find prints nothing: not root-owned or writable.
      await stub('find', 'exit 0');
      final r = await run(g);
      expect(r.exitCode, isNot(0));
      expect(r.stdout, contains('$webGrantUntrustedMarker '));
      expect(r.stdout, isNot(contains(webGrantOkMarker)));
      // No sudo at all: nothing read, merged, checked or installed.
      expect(calls(), isEmpty);
      expect(target.existsSync(), isFalse);
      final probe = WebSudoersGrantProbe(g);
      expect(
        () => probe.parse(r.stdout as String, r.stderr as String, r.exitCode),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            startsWith('Not granted: /usr/sbin/nginx '),
          ),
        ),
      );
    }, skip: Platform.isWindows);

    test('a visudo failure installs nothing', () async {
      await sudoStub();
      await trustedFind();
      await installStub();
      await stub('visudo', 'echo "visudo \$*" >> ${log.path}\nexit 1');
      target.writeAsStringSync('# old\n');
      final r = await run(merge);
      expect(r.exitCode, isNot(0));
      expect(r.stdout, isNot(contains(webGrantOkMarker)));
      expect(calls().where((l) => l.startsWith('install')), isEmpty);
      expect(target.readAsStringSync(), '# old\n');
    }, skip: Platform.isWindows);

    test('a wrong password installs nothing', () async {
      await sudoStub();
      await trustedFind();
      await installStub();
      await stub('visudo', 'exit 0');
      final p = await Process.start(
        'sh',
        ['-c', buildWebGrantScript(merge)],
        environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
      );
      p.stdin.write('wrong\n');
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      expect(await p.exitCode, isNot(0));
      expect(out, isNot(contains(webGrantOkMarker)));
      expect(target.existsSync(), isFalse);
    }, skip: Platform.isWindows);
  });

  group('real visudo accepts the merged file', () {
    final ciRequired = Platform.environment['CI'] == 'true';

    /// The first of [paths] whose `--version` matches [isThisFlavor].
    String? find(List<String> paths, bool Function(String) isThisFlavor) {
      for (final path in paths) {
        if (!File(path).existsSync()) {
          continue;
        }
        final version = Process.runSync(path, ['--version']);
        if (isThisFlavor('${version.stdout}${version.stderr}')) {
          return path;
        }
      }
      return null;
    }

    void check(String label, String? visudo) {
      test(
        'real visudo (classic visudo.ws and sudo-rs visudo) accepts the merged file: $label',
        () async {
          if (visudo == null) {
            expect(ciRequired, isFalse, reason: 'CI must have $label');
            markTestSkipped('$label is not installed here');
            return;
          }
          final dir = Directory.systemTemp.createTempSync('kelola_web_visudo');
          addTearDown(() => dir.deleteSync(recursive: true));
          final target = File('${dir.path}/kelola-web');
          void stub(String name, String body) {
            File('${dir.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
            Process.runSync('chmod', ['+x', '${dir.path}/$name']);
          }

          stub('sudo', '''
shift 3
IFS= read -r pw
for a; do
  shift
  [ "\$a" = $kelolaWebSudoersPath ] && a=${target.path}
  set -- "\$@" "\$a"
done
exec "\$@"''');
          // The script's own visudo call runs the real binary.
          stub('visudo', 'exec $visudo "\$@"');
          // /usr/sbin/nginx is not installed here; trust it.
          stub('find', 'printf "%s\\n" "\$1"');
          stub('install', '''
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');
          target.writeAsStringSync(
            '# Kelola: lens read rules, one command per line. Safe to edit.\n'
            'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service\n',
          );
          final grants = [
            WebSudoersGrant.tryCreate(
              user: 'hendr',
              id: ServiceId.nginx,
              binaries: _nginxBins,
              toolPaths: _tools,
              certPaths: const [
                '/etc/letsencrypt/live/example.com/fullchain.pem',
                '/etc/ssl/certs/b+c@d_e-f.pem',
              ],
              errorLog: '/var/log/nginx/error.log',
              accessLog: '/var/log/nginx/access.log',
            )!,
            WebSudoersGrant.tryCreate(
              user: 'hendr',
              id: ServiceId.apache,
              binaries: const {'apache2ctl': '/usr/sbin/apache2ctl'},
              toolPaths: _tools,
              certPaths: const [
                '/etc/ssl/certs/ssl-cert-snakeoil.pem',
                '/etc/apache2/ssl/site.crt',
              ],
              errorLog: '/var/log/apache2/error.log',
              accessLog: '/var/log/apache2/access.log',
            )!,
          ];
          for (final g in grants) {
            // The same merge as buildWebGrantScript, without its host-side
            // checks (tested on real files below): these paths do not exist
            // here, and the point is visudo's view of the lines.
            final p = await Process.start(
              'sh',
              [
                '-c',
                buildSudoersGrantScript(
                  path: kelolaWebSudoersPath,
                  header: '# Kelola: lens read rules, one command per line. '
                      'Safe to edit.',
                  lines: g.lines,
                  okMarker: webGrantOkMarker,
                ),
              ],
              environment: {'PATH': '${dir.path}:/usr/bin:/bin'},
            );
            p.stdin.write('pw\n');
            await p.stdin.close();
            final out = await p.stdout.transform(utf8.decoder).join();
            final err = await p.stderr.transform(utf8.decoder).join();
            expect(await p.exitCode, 0, reason: '$out$err');
            expect(out, contains(webGrantOkMarker));
          }
          final merged = target.readAsStringSync();
          for (final g in grants) {
            for (final l in g.lines) {
              expect(merged, contains('$l\n'));
            }
          }
          final result = Process.runSync(visudo, ['-c', '-f', target.path]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}${result.stderr}\n$merged',
          );
        },
        skip: Platform.isWindows,
      );
    }

    const paths = ['/usr/sbin/visudo', '/usr/sbin/visudo.ws'];
    check(
      'classic visudo',
      find(paths, (v) => RegExp(r'^visudo(\.ws)? version ').hasMatch(v)),
    );
    check('sudo-rs visudo', find(paths, (v) => v.startsWith('visudo-rs')));
  });

  group('probe', () {
    final g = WebSudoersGrant.tryCreate(
      user: 'hendr',
      id: ServiceId.nginx,
      binaries: _nginxBins,
    )!;
    final probe = WebSudoersGrantProbe(g);

    test('is an audited mutation that never logs the script', () {
      expect(probe.needsSudo, isTrue);
      expect(probe.risk.name, 'mutate');
      expect(probe.auditTitle, contains('nginx'));
      final audit = probe.auditCommand(HostFacts.undiscovered);
      expect(audit, contains(kelolaWebSudoersPath));
      expect(audit, contains(g.linesHash));
      expect(audit, isNot(contains('printf')));
    });

    test('fails unless the host confirmed', () {
      expect(() => probe.parse('', 'boom', 1), throwsA(isA<KelolaException>()));
      expect(() => probe.parse('', '', 0), throwsA(isA<KelolaException>()));
      expect(
        () => probe.parse(unitGrantOkMarker, '', 0),
        throwsA(isA<KelolaException>()),
      );
      probe.parse(webGrantOkMarker, '', 0);
    });

    test('skipped paths: listed, validated, and only fatal when nothing was installed', () {
      final b64 = base64Encode(utf8.encode('/home/deploy/log/error.log'));
      final junk = base64Encode(utf8.encode('/tmp/a b\nroot'));
      final out = '$webGrantSkippedMarker $b64\n'
          '$webGrantSkippedMarker $junk\n$webGrantOkMarker\n';
      expect(probe.parse(out, '', 0).skipped, [
        '/home/deploy/log/error.log',
        'a path',
      ]);
      expect(probe.parse(webGrantOkMarker, '', 0).skipped, isEmpty);
      expect(probe.parse(webGrantOkMarker, '', 0).config, isNull);
      expect(
        webGrantSkippedCopy('/home/deploy/log/error.log'),
        'Not granted: /home/deploy/log/error.log is in a directory that is '
        'not root-owned or is writable by others.',
      );
      expect(
        () => probe.parse('$webGrantSkippedMarker $b64\n', '', 6),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            webGrantSkippedCopy('/home/deploy/log/error.log'),
          ),
        ),
      );
      // Another failure keeps its own error.
      expect(
        () => probe.parse('$webGrantSkippedMarker $b64\n', 'visudo: bad', 1),
        throwsA(
          isA<KelolaException>().having((e) => e.message, 'message', 'visudo: bad'),
        ),
      );
    });

    test('a config refusal is surfaced with its path and reason, validated', () {
      String b64(String p) => base64Encode(utf8.encode(p));
      const p = '/etc/nginx/sites-enabled';
      final copies = {
        'owner': 'Config test not granted: $p is not root-owned.',
        'mode': 'Config test not granted: $p is writable by group or others.',
        'cap': 'Config test not granted: $p has too many config files to '
            'check.',
        'loop': 'Config test not granted: $p is a symlink loop.',
        'missing': 'Config test not granted: $p is missing.',
        'unreadable': 'Config test not granted: $p could not be checked.',
      };
      for (final e in copies.entries) {
        final r = probe.parse(
          '$webGrantConfigMarker ${b64(p)} ${e.key}\n$webGrantOkMarker\n',
          '',
          0,
        );
        expect(r.config?.path, p);
        expect(r.config?.reason.name, e.key);
        expect(webGrantConfigCopy(r.config!), e.value);
        final parts = webGrantConfigCopyParts(r.config!);
        expect('${parts.lead}${parts.path}${parts.tail}', e.value);
        expect(parts.path, p);
      }
      // Forged or broken marker text: never trusted beyond a generic line.
      for (final junk in [
        'not-base64! mode',
        '${b64('/tmp/a b\nroot')} owner',
        '',
        '${b64(p)} rm -rf',
        b64(p),
      ]) {
        final r = probe.parse(
          '$webGrantConfigMarker $junk\n$webGrantOkMarker\n',
          '',
          0,
        );
        expect(r.config, isNotNull, reason: junk);
        final copy = webGrantConfigCopy(r.config!);
        expect(copy, startsWith('Config test not granted: '), reason: junk);
        expect(copy, isNot(contains('\n')), reason: junk);
        expect(copy, isNot(contains('rm -rf')), reason: junk);
      }
      expect(
        webGrantConfigRefusal('$webGrantConfigMarker not-base64! mode\n')!.path,
        'a config file',
      );
      expect(
        webGrantConfigRefusal('$webGrantConfigMarker ${b64(p)} rm\n')!.reason,
        WebConfigRefusalReason.unreadable,
      );
      expect(webGrantConfigRefusal(webGrantOkMarker), isNull);
      // Nothing installed: the refusal is the error, with skipped paths.
      final skip = b64('/home/deploy/log/a.log');
      expect(
        () => probe.parse(
          '$webGrantSkippedMarker $skip\n$webGrantConfigMarker ${b64(p)} owner\n',
          '',
          webGrantNothingExit,
        ),
        throwsA(
          isA<WebGrantRefusedException>()
              .having((e) => e.config?.path, 'config', p)
              .having((e) => e.skipped, 'skipped', ['/home/deploy/log/a.log'])
              .having(
                (e) => e.message,
                'message',
                '${copies['owner']}\n'
                    '${webGrantSkippedCopy('/home/deploy/log/a.log')}',
              ),
        ),
      );
    });

    test('an untrusted binary names itself, validated', () {
      final b64 = base64Encode(utf8.encode('/usr/sbin/nginx'));
      expect(
        () => probe.parse('$webGrantUntrustedMarker $b64\n', '', 5),
        throwsA(
          isA<KelolaException>().having(
            (e) => e.message,
            'message',
            'Not granted: /usr/sbin/nginx is not root-owned or is writable '
                'by others.',
          ),
        ),
      );
      // Even with exit 0 and the OK marker, an untrusted binary fails.
      expect(
        () => probe.parse(
          '$webGrantUntrustedMarker $b64\n$webGrantOkMarker',
          '',
          0,
        ),
        throwsA(isA<KelolaException>()),
      );
      for (final junk in [
        'not-base64!',
        base64Encode(utf8.encode('/tmp/a b\nroot')),
        '',
      ]) {
        expect(
          () => probe.parse('$webGrantUntrustedMarker $junk\n', '', 5),
          throwsA(
            isA<KelolaException>().having(
              (e) => e.message,
              'message',
              'Not granted: a binary is not root-owned or is writable by '
                  'others.',
            ),
          ),
          reason: junk,
        );
      }
    });
  });

  final me = Platform.isWindows
      ? ''
      : (Process.runSync('id', ['-un']).stdout as String).trim();
  // The owners mechanism takes plain names only; anything else cannot run
  // these cases (say why instead of erroring).
  final meOk = RegExp(r'^[a-z_][a-z0-9_-]{0,31}$').hasMatch(me);

  group('binary trust check (real files)', skip: Platform.isWindows || meOk
      ? false
      : '`id -un` gave "$me", which is not a plain owner name', () {
    final isRoot = me == 'root';

    /// Trusted owners for the temp-file cases: root (for `/` and the system
    /// directories above the temp dir) plus the runner, so the permission
    /// branches run on any machine, not only as root.
    final owners = {'root', me}.toList();

    /// Runs the trust snippet under `sh -eu`; returns (exit, stdout).
    Future<(int, String)> check(
      List<String> binaries, {
      List<String> owners = const ['root'],
    }) async {
      final r = await Process.run('sh', [
        '-c',
        'set -eu\n${webBinaryTrustShell(binaries, owners: owners)}'
            'echo CHECK_PASSED',
      ]);
      return (r.exitCode, r.stdout as String);
    }

    String? untrusted(String out) {
      final m = RegExp(
        '^$webGrantUntrustedMarker (\\S+)\$',
        multiLine: true,
      ).firstMatch(out);
      return m == null ? null : utf8.decode(base64Decode(m.group(1)!));
    }

    late Directory dir;
    var baseClean = false;

    setUpAll(() async {
      // A base whose whole chain is clean for [owners]; /tmp never is (it
      // is world-writable). Try the repo's .dart_tool, then $HOME.
      for (final base in [
        '${Directory.current.path}/.dart_tool',
        Platform.environment['HOME'] ?? '',
      ]) {
        if (base.isEmpty || !Directory(base).existsSync()) continue;
        final probe = Directory(base).createTempSync('kelola_trust_base');
        Process.runSync('chmod', ['755', probe.path]);
        final f = File('${probe.path}/x')..writeAsStringSync('');
        Process.runSync('chmod', ['755', f.path]);
        final (rc, _) = await check([f.path], owners: owners);
        probe.deleteSync(recursive: true);
        if (rc == 0) {
          baseClean = true;
          dir = Directory(base);
          return;
        }
      }
    });

    late Directory root;

    setUp(() {
      if (!baseClean) return;
      root = dir.createTempSync('kelola_trust');
      Process.runSync('chmod', ['755', root.path]);
    });

    tearDown(() {
      if (!baseClean) return;
      Process.runSync('chmod', ['-R', 'u+rwx', root.path]);
      root.deleteSync(recursive: true);
    });

    /// A 0755 directory under the test root.
    Directory sub(String name, {String mode = '755'}) {
      final d = Directory('${root.path}/$name')..createSync(recursive: true);
      Process.runSync('chmod', [mode, d.path]);
      return d;
    }

    File exe(String path, {String mode = '755'}) {
      final f = File(path)..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', [mode, f.path]);
      return f;
    }

    /// Skips unless a clean base was found (see [setUpAll]).
    bool ready() {
      if (Platform.isWindows) return false;
      if (!baseClean) {
        markTestSkipped('no directory with a clean owner chain here');
        return false;
      }
      return true;
    }

    test('production checks root ownership and nothing else', () {
      final grant = WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: ServiceId.nginx,
        binaries: _nginxBins,
        toolPaths: _tools,
      )!;
      for (final sh in [
        buildWebGrantScript(grant),
        webBinaryTrustShell(['/usr/sbin/nginx']),
      ]) {
        final users = RegExp(r"-user '([^']*)'").allMatches(sh).toList();
        expect(users, isNotEmpty);
        expect(users.map((m) => m.group(1)).toSet(), {'root'});
        expect(RegExp(r'-user\b').allMatches(sh).length, users.length);
        // No `readlink -f`: every hop is checked, one at a time.
        expect(sh, isNot(contains('readlink -f')));
        expect(sh, isNot(contains('-perm /')));
      }
      expect(
        () => webBinaryTrustShell(['/x'], owners: ["root' -o -user 'x"]),
        throwsArgumentError,
      );
      expect(
        () => webBinaryTrustShell(['/x'], owners: []),
        throwsArgumentError,
      );
    });

    test('a root-owned system binary passes', () async {
      final (rc, out) = await check(['/usr/bin/tail']);
      expect(rc, 0, reason: out);
      expect(out, contains('CHECK_PASSED'));
    }, skip: !Platform.isLinux);

    test('a clean file passes', () async {
      if (!ready()) return;
      final f = exe('${sub('sbin').path}/nginx');
      final (rc, out) = await check([f.path, '/usr/bin/tail'], owners: owners);
      expect(rc, 0, reason: out);
      expect(out, contains('CHECK_PASSED'));
    });

    test('a group-writable file fails', () async {
      if (!ready()) return;
      final f = exe('${sub('sbin').path}/nginx', mode: '775');
      final (rc, out) = await check(['/usr/bin/tail', f.path], owners: owners);
      expect(rc, isNot(0));
      expect(out, isNot(contains('CHECK_PASSED')));
      expect(untrusted(out), f.path);
    });

    test('an other-writable file fails', () async {
      if (!ready()) return;
      final f = exe('${sub('sbin').path}/nginx', mode: '757');
      final (rc, out) = await check([f.path], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    });

    test('an other-writable directory fails', () async {
      if (!ready()) return;
      final f = exe('${sub('sbin', mode: '777').path}/nginx');
      final (rc, out) = await check([f.path], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    });

    test('a writable parent further up fails', () async {
      if (!ready()) return;
      sub('a', mode: '775');
      final f = exe('${sub('a/b').path}/nginx');
      final (rc, out) = await check([f.path], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    });

    test('a symlink to a writable target fails', () async {
      if (!ready()) return;
      final target = exe('${sub('bad', mode: '777').path}/nginx');
      final link = Link('${sub('sbin').path}/nginx')..createSync(target.path);
      final (rc, out) = await check([link.path], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), link.path);
    });

    test('a writable directory holding an intermediate hop fails', () async {
      if (!ready()) return;
      // sbin/nginx -> w/hop -> lib/nginx: the final file and its directory
      // are clean, but whoever can write w/ can repoint hop.
      final real = exe('${sub('lib').path}/nginx');
      final hop = Link('${sub('w', mode: '777').path}/hop')
        ..createSync(real.path);
      final link = Link('${sub('sbin').path}/nginx')..createSync(hop.path);
      final (rc, out) = await check([link.path], owners: owners);
      expect(rc, isNot(0), reason: out);
      expect(untrusted(out), link.path);
    });

    test('a clean chain of hops passes', () async {
      if (!ready()) return;
      final real = exe('${sub('lib/x').path}/nginx');
      final hop2 = Link('${sub('b').path}/hop2')..createSync(real.path);
      final hop1 = Link('${sub('a').path}/hop1')..createSync(hop2.path);
      final link = Link('${sub('sbin').path}/nginx')..createSync(hop1.path);
      final (rc, out) = await check([link.path], owners: owners);
      expect(rc, 0, reason: out);
      expect(out, contains('CHECK_PASSED'));
    });

    test('a relative hop resolves against the link directory', () async {
      if (!ready()) return;
      exe('${sub('lib').path}/nginx');
      final good = Link('${sub('sbin').path}/nginx')
        ..createSync('../lib/nginx');
      var (rc, out) = await check([good.path], owners: owners);
      expect(rc, 0, reason: out);

      // Relative to the link's directory, not the shell's: `bad` holds a
      // writable directory only reachable that way.
      exe('${sub('bad', mode: '777').path}/nginx');
      final bad = Link('${sub('sbin2').path}/nginx')
        ..createSync('../bad/./nginx');
      (rc, out) = await check([bad.path], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), bad.path);
    });

    test('a symlink loop fails by the hop bound', () async {
      if (!ready()) return;
      final d = sub('sbin');
      Link('${d.path}/a').createSync('${d.path}/b');
      Link('${d.path}/b').createSync('${d.path}/a');
      final (rc, out) = await check(['${d.path}/a'], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), '${d.path}/a');
      // A long but finite chain under the bound still passes.
      final real = exe('${d.path}/real');
      var prev = real.path;
      for (var i = 0; i < 30; i++) {
        Link('${d.path}/l$i').createSync(prev);
        prev = '${d.path}/l$i';
      }
      final (ok, okOut) = await check([prev], owners: owners);
      expect(ok, 0, reason: okOut);
      // Past the bound fails.
      for (var i = 30; i < 45; i++) {
        Link('${d.path}/l$i').createSync(prev);
        prev = '${d.path}/l$i';
      }
      final (long, _) = await check([prev], owners: owners);
      expect(long, isNot(0));
    });

    test(
      'a root-owned file reached through a user-owned symlink fails',
      () async {
        if (!isRoot) {
          markTestSkipped('needs root to own the link as another user');
          return;
        }
        if (!ready()) return;
        final link = Link('${sub('sbin').path}/tail')
          ..createSync('/usr/bin/tail');
        Process.runSync('chown', ['-h', 'nobody', link.path]);
        final (rc, out) = await check([link.path]);
        expect(rc, isNot(0));
        expect(untrusted(out), link.path);
      },
    );

    test('a missing binary fails', () async {
      if (!ready()) return;
      final (rc, out) = await check(['${root.path}/nope'], owners: owners);
      expect(rc, isNot(0));
      expect(untrusted(out), '${root.path}/nope');
    });

    test('a readlink target ending in a newline fails closed', () async {
      if (!ready()) return;
      // `$(...)` strips trailing newlines, so the walk would check `real`
      // while the kernel follows `real<newline>`.
      final d = sub('sbin');
      exe('${d.path}/real');
      exe('${d.path}/real\n', mode: '777');
      final link = Link('${d.path}/nginx')..createSync('${d.path}/real\n');
      final (rc, out) = await check([link.path], owners: owners);
      expect(rc, isNot(0), reason: out);
      expect(untrusted(out), link.path);
      final mid = Link('${d.path}/mid')..createSync('real\nx');
      final (rc2, out2) = await check([mid.path], owners: owners);
      expect(rc2, isNot(0), reason: out2);
    });

    /// Runs the path checks; returns the skipped paths (decoded).
    Future<List<String>> skippedOf(List<String> paths) async {
      final r = await Process.run('sh', [
        '-c',
        'set -eu\n${webBinaryTrustShell(const [], paths: paths, owners: owners)}'
            'echo CHECK_PASSED',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(r.stdout, contains('CHECK_PASSED'));
      return webGrantSkippedPaths(r.stdout as String);
    }

    test('a log in a writable directory is skipped, a clean one kept', () async {
      if (!ready()) return;
      final good = File('${sub('log').path}/error.log')..writeAsStringSync('x');
      final bad = File('${sub('app/log', mode: '777').path}/error.log')
        ..writeAsStringSync('x');
      final upper = File('${sub('w/x').path}/access.log')
        ..writeAsStringSync('x');
      Process.runSync('chmod', ['775', '${root.path}/w']);
      expect(await skippedOf([good.path, bad.path, upper.path]), [
        bad.path,
        upper.path,
      ]);
    });

    test('a log file itself may be owned by anyone or writable', () async {
      if (!ready()) return;
      // tail only reads it; only who can replace it (its directory) counts.
      final f = File('${sub('log').path}/access.log')..writeAsStringSync('x');
      Process.runSync('chmod', ['666', f.path]);
      if (isRoot) Process.runSync('chown', ['nobody', f.path]);
      expect(await skippedOf([f.path]), isEmpty);
    });

    test('a symlinked log planted in a writable directory is skipped', () async {
      if (!ready()) return;
      final d = sub('app/log', mode: '777');
      final link = Link('${d.path}/error.log')..createSync('/etc/shadow');
      // A clean link to it does not launder it either.
      final via = Link('${sub('log').path}/error.log')..createSync(link.path);
      expect(await skippedOf([link.path, via.path]), [link.path, via.path]);
    });

    test('a cert through a user-owned symlink is skipped', () async {
      if (!isRoot) {
        markTestSkipped('needs root to own the link as another user');
        return;
      }
      if (!ready()) return;
      final link = Link('${sub('certs').path}/site.pem')
        ..createSync('/etc/shadow');
      Process.runSync('chown', ['-h', 'nobody', link.path]);
      final real = File('${sub('real').path}/site.pem')..writeAsStringSync('');
      final clean = Link('${sub('live').path}/site.pem')..createSync(real.path);
      expect(await skippedOf([link.path, clean.path]), [link.path]);
    });

    test('a missing path, a directory or `/` is skipped', () async {
      if (!ready()) return;
      final d = sub('log');
      expect(await skippedOf(['${d.path}/nope.log', d.path, '/']), [
        '${d.path}/nope.log',
        d.path,
        // Not a plain path: named generically.
        'a path',
      ]);
    });

    group('grant script with real files', () {
      late Directory bin;
      late File target;
      late File log;

      setUp(() {
        if (!baseClean) return;
        bin = Directory.systemTemp.createTempSync('kelola_web_stub');
        target = File('${bin.path}/kelola-web');
        log = File('${bin.path}/calls.log');
        void stub(String name, String body) {
          File('${bin.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
          Process.runSync('chmod', ['+x', '${bin.path}/$name']);
        }

        stub('sudo', '''
[ "\$1" = -S ] || exit 9
shift 3
IFS= read -r pw
for a; do
  shift
  [ "\$a" = $kelolaWebSudoersPath ] && a=${target.path}
  set -- "\$@" "\$a"
done
echo "sudo \$1" >> ${log.path}
exec "\$@"''');
        stub('visudo', 'exit 0');
        stub('install', '''
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');
      });

      tearDown(() {
        if (baseClean) bin.deleteSync(recursive: true);
      });

      Future<ProcessResult> run(WebSudoersGrant g) async {
        final p = await Process.start(
          'sh',
          ['-c', buildWebGrantScript(g, trustOwners: owners)],
          // Real find, readlink and base64.
          environment: {'PATH': '${bin.path}:/usr/bin:/bin'},
        );
        p.stdin.write('pw\n');
        await p.stdin.close();
        final out = await p.stdout.transform(utf8.decoder).join();
        final err = await p.stderr.transform(utf8.decoder).join();
        return ProcessResult(p.pid, await p.exitCode, out, err);
      }

      /// openssl and tail as they sit on this machine, if their chain is
      /// clean (the binaries stay all-or-nothing).
      Future<Map<String, String>?> tools() async {
        const t = {'openssl': '/usr/bin/openssl', 'tail': '/usr/bin/tail'};
        for (final p in t.values) {
          if (!File(p).existsSync()) return null;
        }
        final (rc, _) = await check(t.values.toList());
        return rc == 0 ? t : null;
      }

      test('skipped lines left out, the rest installed, one marker each', () async {
        if (!ready()) return;
        final t = await tools();
        if (t == null) {
          markTestSkipped('/usr/bin/openssl or /usr/bin/tail missing here');
          return;
        }
        final goodCert = File('${sub('certs').path}/a.pem')
          ..writeAsStringSync('');
        final badCert = Link('${sub('home/certs', mode: '777').path}/b.pem')
          ..createSync('/etc/shadow');
        final badLog = Link('${sub('home/log', mode: '777').path}/error.log')
          ..createSync('/etc/shadow');
        final goodLog = File('${sub('log').path}/access.log')
          ..writeAsStringSync('');
        final g = WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.nginx,
          binaries: const {},
          toolPaths: t,
          certPaths: [goodCert.path, badCert.path],
          errorLog: badLog.path,
          accessLog: goodLog.path,
        )!;
        expect(g.lines, hasLength(4));
        final r = await run(g);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, contains(webGrantOkMarker));
        expect(webGrantSkippedPaths(r.stdout as String), [
          badCert.path,
          badLog.path,
        ]);
        expect(target.readAsLinesSync(), [
          '# Kelola: lens read rules, one command per line. Safe to edit.',
          g.lines[0],
          g.lines[3],
        ]);
        final skipped = WebSudoersGrantProbe(
          g,
        ).parse(r.stdout as String, r.stderr as String, r.exitCode);
        expect(skipped.skipped, [badCert.path, badLog.path]);
      });

      test('a clean root chain installs every line', () async {
        if (!ready()) return;
        final t = await tools();
        if (t == null) {
          markTestSkipped('/usr/bin/openssl or /usr/bin/tail missing here');
          return;
        }
        final cert = File('${sub('real').path}/a.pem')..writeAsStringSync('');
        final live = Link('${sub('live').path}/a.pem')..createSync(cert.path);
        final err = File('${sub('log').path}/error.log')..writeAsStringSync('');
        final g = WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.nginx,
          binaries: const {},
          toolPaths: t,
          certPaths: [live.path],
          errorLog: err.path,
          accessLog: err.path,
        )!;
        final r = await run(g);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, isNot(contains(webGrantSkippedMarker)));
        expect(target.readAsLinesSync().skip(1), g.lines);
        expect(
          WebSudoersGrantProbe(g).parse(r.stdout as String, '', 0).skipped,
          isEmpty,
        );
      });

      test('every line skipped: nothing read or installed', () async {
        if (!ready()) return;
        final t = await tools();
        if (t == null) {
          markTestSkipped('/usr/bin/openssl or /usr/bin/tail missing here');
          return;
        }
        final d = sub('home/log', mode: '777');
        final err = Link('${d.path}/error.log')..createSync('/etc/shadow');
        final g = WebSudoersGrant.tryCreate(
          user: 'hendr',
          id: ServiceId.nginx,
          binaries: const {},
          toolPaths: t,
          errorLog: err.path,
          accessLog: '${d.path}/access.log',
        )!;
        final r = await run(g);
        expect(r.exitCode, 6, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, isNot(contains(webGrantOkMarker)));
        expect(target.existsSync(), isFalse);
        expect(log.existsSync(), isFalse, reason: 'no sudo call at all');
        expect(
          () => WebSudoersGrantProbe(
            g,
          ).parse(r.stdout as String, r.stderr as String, r.exitCode),
          throwsA(
            isA<KelolaException>().having(
              (e) => e.message,
              'message',
              '${webGrantSkippedCopy(err.path)}\n'
                  '${webGrantSkippedCopy('${d.path}/access.log')}',
            ),
          ),
        );
      });
    });

    // Fix 1: the config test (`-t`, `-T` / `-S`) runs as root and loads the
    // modules the server config names, so its lines are only installed when
    // the config tree, the module directories and every dump-named file are
    // root-controlled. Each case runs the whole grant script, under dash and
    // under busybox sh with busybox's own find, readlink, base64 and test.
    group('config trust gate (real trees)', () {
      late Directory bin;
      late File target;
      late File log;
      String? bbDir;
      final hasDash =
          !Platform.isWindows &&
          Process.runSync('sh', ['-c', 'command -v dash']).exitCode == 0;

      setUpAll(() {
        if (Platform.isWindows) return;
        final which = Process.runSync('sh', ['-c', 'command -v busybox']);
        final bb = (which.stdout as String).trim();
        if (which.exitCode != 0 || bb.isEmpty) return;
        final d = Directory.systemTemp.createTempSync('kelola_bb');
        final r = Process.runSync(bb, ['--install', '-s', d.path]);
        if (r.exitCode == 0 && File('${d.path}/find').existsSync()) {
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
        if (!baseClean) return;
        bin = Directory.systemTemp.createTempSync('kelola_cfg_stub');
        // The untraversable-directory case runs the script as `nobody`.
        Process.runSync('chmod', ['777', bin.path]);
        target = File('${bin.path}/kelola-web');
        log = File('${bin.path}/calls.log');
        void stub(String name, String body) {
          File('${bin.path}/$name').writeAsStringSync('#!/bin/sh\n$body\n');
          Process.runSync('chmod', ['755', '${bin.path}/$name']);
        }

        stub('sudo', '''
[ "\$1" = -S ] || exit 9
shift 3
IFS= read -r pw
for a; do
  shift
  [ "\$a" = $kelolaWebSudoersPath ] && a=${target.path}
  set -- "\$@" "\$a"
done
echo "sudo \$1" >> ${log.path}
exec "\$@"''');
        stub('visudo', 'exit 0');
        stub('install', '''
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');
      });

      tearDown(() {
        if (baseClean) bin.deleteSync(recursive: true);
      });

      String b64(String s) => base64Encode(utf8.encode(s));

      /// The grant script with the test-only config prefix, and the server
      /// binary (`/usr/sbin/...`, the only place a line may name) swapped
      /// for [serverStub] in the host-side checks.
      String scriptFor(WebSudoersGrant g, String serverStub) {
        final real = g.binaries.first;
        final s = buildWebGrantScript(
          g,
          trustOwners: owners,
          configPrefix: root.path,
        );
        expect(s, contains("'${b64(real)}'"));
        return s.replaceAll("'${b64(real)}'", "'${b64(serverStub)}'");
      }

      /// Runs [script] under [shell]; [asUser] (root only) drops to that
      /// user first.
      Future<ProcessResult> run(
        String script,
        String shell, {
        String? asUser,
      }) async {
        final path = shell == 'busybox'
            ? '${bin.path}:$bbDir'
            : '${bin.path}:/usr/bin:/bin';
        final argv = shell == 'busybox'
            ? ['busybox', 'sh', '-c', script]
            : ['dash', '-c', script];
        final cmd = asUser == null
            ? ['env', 'PATH=$path', ...argv]
            : [
                'setpriv',
                '--reuid=$asUser',
                '--regid=${(Process.runSync('id', ['-g', asUser]).stdout as String).trim()}',
                '--clear-groups',
                '--',
                'env',
                'PATH=$path',
                ...argv,
              ];
        final p = await Process.start(cmd.first, cmd.sublist(1));
        p.stdin.write('pw\n');
        await p.stdin.close();
        final out = await p.stdout.transform(utf8.decoder).join();
        final err = await p.stderr.transform(utf8.decoder).join();
        return ProcessResult(p.pid, await p.exitCode, out, err);
      }

      List<String> calls() => log.existsSync() ? log.readAsLinesSync() : [];

      File file(String path, {String mode = '644', String body = ''}) {
        final f = File(path)..writeAsStringSync(body);
        Process.runSync('chmod', [mode, f.path]);
        return f;
      }

      /// A Debian-like nginx tree under the test root, and a stub nginx
      /// whose `-V` names it.
      ({String stub, Directory conf}) nginxTree() {
        final conf = sub('etc/nginx');
        file('${conf.path}/nginx.conf', body: 'events {}\n');
        file('${conf.path}/mime.types');
        sub('etc/nginx/conf.d');
        sub('etc/nginx/sites-available');
        file('${sub('etc/nginx/sites-enabled').path}/default');
        sub('etc/nginx/modules-enabled');
        final stub = file(
          '${sub('sbin').path}/nginx',
          mode: '755',
          body: '#!/bin/sh\n'
              '[ "\$1" = -V ] || exit 1\n'
              'echo "nginx version: nginx/1.24.0 (Ubuntu)" >&2\n'
              "echo \"configure arguments: --with-cc-opt='-g -O2' "
              '--prefix=/usr/share/nginx --conf-path=${conf.path}/nginx.conf '
              '--http-log-path=/var/log/nginx/access.log" >&2\n',
        );
        return (stub: stub.path, conf: conf);
      }

      ({String stub, Directory conf}) apacheTree({String envvars = '644'}) {
        final conf = sub('etc/apache2');
        file('${conf.path}/apache2.conf');
        file('${conf.path}/envvars', mode: envvars, body: 'export X=1\n');
        file('${sub('etc/apache2/sites-enabled').path}/000-default.conf');
        file('${sub('etc/apache2/mods-enabled').path}/ssl.load');
        final stub = file('${sub('sbin').path}/apachectl', mode: '755');
        return (stub: stub.path, conf: conf);
      }

      late Map<String, String> tools;

      /// Skips (with the reason) unless the tree and the tools can be used.
      Future<bool> go(String shell) async {
        if (!ready()) return false;
        if (shell == 'busybox' && bbDir == null) {
          markTestSkipped('busybox is not installed here');
          return false;
        }
        if (shell == 'dash' && !hasDash) {
          markTestSkipped('dash is not installed here');
          return false;
        }
        const t = {'openssl': '/usr/bin/openssl', 'tail': '/usr/bin/tail'};
        for (final p in t.values) {
          if (!File(p).existsSync()) {
            markTestSkipped('$p missing here');
            return false;
          }
        }
        final (rc, _) = await check(t.values.toList());
        if (rc != 0) {
          markTestSkipped('/usr/bin/openssl or /usr/bin/tail is not clean');
          return false;
        }
        tools = t;
        return true;
      }

      String cert() =>
          file('${sub('certs').path}/a.pem').path;

      WebSudoersGrant grant(
        ServiceId id, {
        String? certPath,
        List<String> configFiles = const [],
      }) => WebSudoersGrant.tryCreate(
        user: 'hendr',
        id: id,
        binaries: id == ServiceId.apache
            ? const {'apachectl': '/usr/sbin/apachectl'}
            : _nginxBins,
        toolPaths: tools,
        certPaths: [?certPath],
        configFiles: configFiles,
      )!;

      bool configLine(String l) =>
          l.endsWith(' -t') || l.endsWith(' -T') || l.endsWith(' -S');

      void expectKept(ProcessResult r, WebSudoersGrant g) {
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, isNot(contains(webGrantConfigMarker)));
        expect(target.readAsLinesSync().skip(1), g.lines);
        expect(g.lines.where(configLine), hasLength(2));
        final res = WebSudoersGrantProbe(
          g,
        ).parse(r.stdout as String, r.stderr as String, r.exitCode);
        expect(res.config, isNull);
      }

      void expectDropped(
        ProcessResult r,
        WebSudoersGrant g, {
        required Object path,
        required WebConfigRefusalReason reason,
      }) {
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, contains(webGrantOkMarker));
        // Only the config test lines are left out; the cert line stays.
        final kept = [
          for (final l in g.lines)
            if (!configLine(l)) l,
        ];
        expect(kept, isNotEmpty);
        expect(target.readAsLinesSync().skip(1), kept);
        final res = WebSudoersGrantProbe(
          g,
        ).parse(r.stdout as String, r.stderr as String, r.exitCode);
        expect(res.skipped, isEmpty);
        expect(res.config, isNotNull, reason: '${r.stdout}');
        expect(res.config!.path, path, reason: '${r.stdout}');
        expect(res.config!.reason, reason, reason: '${r.stdout}');
        // One marker, before anything was read.
        expect(
          webGrantConfigMarker.allMatches(r.stdout as String),
          hasLength(1),
        );
      }

      for (final shell in const ['dash', 'busybox']) {
        test('$shell: a root-owned tree keeps the config test lines', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          // Debian's dangling /usr/share/nginx/modules link, in a clean
          // chain: only root could create its target, so it is skipped.
          sub('usr/share/nginx');
          Link('${root.path}/usr/share/nginx/modules')
              .createSync('../../lib/nginx/modules');
          file('${sub('usr/lib64/nginx/modules').path}/ngx_stream.so');
          final g = grant(
            ServiceId.nginx,
            certPath: cert(),
            configFiles: ['${t.conf.path}/nginx.conf'],
          );
          final r = await run(scriptFor(g, t.stub), shell);
          expectKept(r, g);
        });

        test('$shell: a group-writable sites-enabled drops -t and -T, keeps the cert line', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          Process.runSync('chmod', ['775', '${t.conf.path}/sites-enabled']);
          final g = grant(ServiceId.nginx, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: '${t.conf.path}/sites-enabled',
            reason: WebConfigRefusalReason.mode,
          );
        });

        test('$shell: a user-owned include outside the root, known from the dump, drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          final inc = file('${sub('opt/letsencrypt').path}/options-ssl-nginx.conf');
          // Not root-owned needs root to set up; without root the same file
          // is made group-writable instead.
          if (isRoot) {
            Process.runSync('chown', ['nobody', inc.path]);
          } else {
            Process.runSync('chmod', ['664', inc.path]);
          }
          final g = grant(
            ServiceId.nginx,
            certPath: cert(),
            configFiles: ['${t.conf.path}/nginx.conf', inc.path],
          );
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: inc.path,
            reason: isRoot
                ? WebConfigRefusalReason.owner
                : WebConfigRefusalReason.mode,
          );
          // The same include, clean: kept.
          Process.runSync('chmod', ['644', inc.path]);
          if (isRoot) Process.runSync('chown', ['root', inc.path]);
          target.deleteSync();
          expectKept(await run(scriptFor(g, t.stub), shell), g);
        });

        test('$shell: a writable module directory drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          final mods = sub('usr/lib/nginx/modules', mode: '775');
          file('${mods.path}/ngx_http_geoip_module.so');
          final g = grant(ServiceId.nginx, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: mods.path,
            reason: WebConfigRefusalReason.mode,
          );
        });

        test('$shell: a dangling module link through a writable directory drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          sub('usr/share/nginx');
          final w = sub('usr/lib', mode: '777');
          Link('${root.path}/usr/share/nginx/modules')
              .createSync('../../lib/nginx/modules');
          final g = grant(ServiceId.nginx, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: w.path,
            reason: WebConfigRefusalReason.mode,
          );
        });

        test('$shell: a symlink into a user-writable directory drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          final w = sub('home/deploy', mode: '777');
          final site = file('${w.path}/shop.conf');
          Link('${t.conf.path}/sites-enabled/shop.conf').createSync(site.path);
          final g = grant(ServiceId.nginx, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: w.path,
            reason: WebConfigRefusalReason.mode,
          );
        });

        test('$shell: a symlinked directory is scanned too', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          // The link and the directory it names are clean, but a file
          // inside it is writable by others.
          final shared = sub('srv/nginx-shared');
          file('${shared.path}/upstreams.conf', mode: '666');
          Link('${t.conf.path}/shared').createSync(shared.path);
          final g = grant(ServiceId.nginx, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: '${shared.path}/upstreams.conf',
            reason: WebConfigRefusalReason.mode,
          );
        });

        test('$shell: a symlink loop drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          // A directory link back up the tree.
          final loop = Link('${t.conf.path}/sites-enabled/loop')
            ..createSync(t.conf.path);
          final g = grant(ServiceId.nginx, certPath: cert());
          var r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: loop.path,
            reason: WebConfigRefusalReason.loop,
          );
          // The same loop written as `..`: the walk never ends on `..`, so
          // it fails closed before the loop check.
          loop.deleteSync();
          Link(loop.path).createSync('..');
          target.deleteSync();
          expectDropped(
            await run(scriptFor(g, t.stub), shell),
            g,
            path: loop.path,
            reason: WebConfigRefusalReason.unreadable,
          );
          // Two links naming each other.
          loop.deleteSync();
          Link('${t.conf.path}/sites-enabled/a').createSync('b');
          Link('${t.conf.path}/sites-enabled/b').createSync('a');
          target.deleteSync();
          r = await run(scriptFor(g, t.stub), shell);
          final res = WebSudoersGrantProbe(g).parse(r.stdout as String, '', 0);
          expect(res.config?.reason, WebConfigRefusalReason.loop);
          expect(res.config?.path, startsWith('${t.conf.path}/sites-enabled/'));
          expect(target.readAsLinesSync().skip(1), [
            for (final l in g.lines)
              if (!configLine(l)) l,
          ]);
        });

        test('$shell: reaching the entry cap drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          final many = sub('etc/nginx/conf.d/many');
          for (var i = 0; i < webConfigTrustMaxEntries; i++) {
            File('${many.path}/f$i.conf').writeAsStringSync('');
          }
          final g = grant(ServiceId.nginx, certPath: cert());
          final sw = Stopwatch()..start();
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: t.conf.path,
            reason: WebConfigRefusalReason.cap,
          );
          expect(sw.elapsed, lessThan(const Duration(seconds: 30)));
        });

        test('$shell: a writable Apache envvars drops -t and -S', () async {
          if (!await go(shell)) return;
          final t = apacheTree(envvars: '664');
          final g = grant(ServiceId.apache, certPath: cert());
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: '${t.conf.path}/envvars',
            reason: WebConfigRefusalReason.mode,
          );
          Process.runSync('chmod', ['644', '${t.conf.path}/envvars']);
          target.deleteSync();
          expectKept(await run(scriptFor(g, t.stub), shell), g);
        });

        test('$shell: a dump-named file that cannot go in a check drops them', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          final g = grant(
            ServiceId.nginx,
            certPath: cert(),
            configFiles: ['${t.conf.path}/odd name.conf'],
          );
          final r = await run(scriptFor(g, t.stub), shell);
          expectDropped(
            r,
            g,
            path: 'a config file',
            reason: WebConfigRefusalReason.unreadable,
          );
        });

        test('$shell: only config test lines, dropped: nothing read or installed', () async {
          if (!await go(shell)) return;
          final t = nginxTree();
          Process.runSync('chmod', ['775', '${t.conf.path}/sites-enabled']);
          final g = grant(ServiceId.nginx);
          expect(g.lines.every(configLine), isTrue);
          final r = await run(scriptFor(g, t.stub), shell);
          expect(r.exitCode, webGrantNothingExit, reason: '${r.stdout}${r.stderr}');
          expect(r.stdout, isNot(contains(webGrantOkMarker)));
          expect(target.existsSync(), isFalse);
          expect(calls(), isEmpty, reason: 'no sudo call at all');
          expect(
            () => WebSudoersGrantProbe(
              g,
            ).parse(r.stdout as String, r.stderr as String, r.exitCode),
            throwsA(
              isA<WebGrantRefusedException>()
                  .having(
                    (e) => e.config?.path,
                    'config path',
                    '${t.conf.path}/sites-enabled',
                  )
                  .having(
                    (e) => e.message,
                    'message',
                    'Config test not granted: ${t.conf.path}/sites-enabled '
                        'is writable by group or others.',
                  ),
            ),
          );
        });

        test('$shell: a root-owned 0700 directory the login cannot enter is still trusted', () async {
          if (!isRoot) {
            markTestSkipped(
              'needs root to build a root-owned tree and run as nobody',
            );
            return;
          }
          if (!await go(shell)) return;
          final t = nginxTree();
          final private = sub('etc/nginx/private', mode: '700');
          file('${private.path}/dhparam.pem', mode: '600');
          final g = grant(ServiceId.nginx, certPath: cert());
          // The login (nobody) cannot traverse private/, so find would
          // fail there without the ruling-3 prune.
          final r = await run(scriptFor(g, t.stub), shell, asUser: 'nobody');
          expectKept(r, g);
          // Untraversable but group-writable: untrusted all the same.
          Process.runSync('chmod', ['730', private.path]);
          target.deleteSync();
          final r2 = await run(scriptFor(g, t.stub), shell, asUser: 'nobody');
          expectDropped(
            r2,
            g,
            path: private.path,
            reason: WebConfigRefusalReason.mode,
          );
          // A module directory the login cannot see because another user's
          // 0700 directory hides it is not "absent": that user could plant
          // modules there.
          Process.runSync('chmod', ['700', private.path]);
          final hidden = sub('usr/lib64', mode: '700');
          Process.runSync('chown', ['daemon', hidden.path]);
          target.deleteSync();
          final r3 = await run(scriptFor(g, t.stub), shell, asUser: 'nobody');
          expectDropped(
            r3,
            g,
            path: hidden.path,
            reason: WebConfigRefusalReason.owner,
          );
        });
      }
    });

    test('binaries are carried encoded, never raw', () {
      final sh = webBinaryTrustShell(['/usr/sbin/nginx']);
      expect(sh, contains(base64Encode(utf8.encode('/usr/sbin/nginx'))));
      expect(sh, isNot(contains('/usr/sbin/nginx')));
    });
  });

  test('the sudo hint names the one lens file', () {
    final hint = kelolaSudoHint(
      user: 'hendr',
      context: SudoHintContext.webServices(service: 'nginx'),
    );
    expect(hint.body, contains(kelolaWebSudoersPath));
    expect(
      File('lib/domain/sudo_hint.dart').readAsStringSync(),
      isNot(contains("'/etc/sudoers.d/kelola-web'")),
    );
  });

  test('OpenRC reload hint offers no lens grant', () {
    final hint = kelolaSudoHint(
      user: 'hendr',
      context: SudoHintContext.webServices(
        service: 'nginx',
        binary: 'rc-service',
      ),
    );
    expect(hint.body, isNot(contains('Grant read access')));
    expect(hint.body, contains('rc-service'));
    expect(hint.snippet, isNot(contains('NOPASSWD: <nginx>')));
  });
}
