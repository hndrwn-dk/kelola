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

    test(
      'existing lines kept, missing added once, visudo before install',
      () async {
        await sudoStub();
        await trustedFind();
        await installStub();
        await stub('visudo', 'echo "visudo \$*" >> ${log.path}');
        const unrelated = 'hendr ALL=(root) NOPASSWD: /usr/bin/du -sh /srv';
        target.writeAsStringSync('# my notes\n$unrelated\n${g.lines[2]}\n');

        final r = await run(g);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, contains(webGrantOkMarker));
        final lines = target.readAsLinesSync();
        expect(lines.take(3), ['# my notes', unrelated, g.lines[2]]);
        expect(lines.skip(3), [
          for (final l in g.lines)
            if (l != g.lines[2]) l,
        ]);
        final c = calls();
        final visudo = c.indexWhere((l) => l.startsWith('visudo -c -f'));
        final install = c.indexWhere(
          (l) => l.startsWith('install -o root -g root -m 0440'),
        );
        expect(visudo, greaterThanOrEqualTo(0), reason: '$c');
        expect(install, greaterThan(visudo), reason: '$c');

        // Run again: nothing is added twice.
        final again = await run(g);
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
      final r = await run(g);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      expect(target.readAsLinesSync(), [
        '# Kelola: lens read rules, one command per line. Safe to edit.',
        ...g.lines,
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
      final r = await run(g);
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
        ['-c', buildWebGrantScript(g)],
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
            final p = await Process.start(
              'sh',
              ['-c', buildWebGrantScript(g)],
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

  group('binary trust check (real files)', () {
    final isRoot =
        Platform.isLinux &&
        (Process.runSync('id', ['-u']).stdout as String).trim() == '0';
    late Directory dir;

    setUp(() {
      // Not under /tmp: the check walks every parent, and /tmp is world
      // writable. The repo's .dart_tool is root-owned 0755 in this container.
      dir = Directory('${Directory.current.path}/.dart_tool')
          .createTempSync('kelola_trust');
      Process.runSync('chmod', ['755', dir.path]);
    });

    tearDown(() {
      Process.runSync('chmod', ['-R', 'u+rwx', dir.path]);
      dir.deleteSync(recursive: true);
    });

    /// Runs the trust snippet under `sh -eu`; returns (exit, stdout).
    Future<(int, String)> check(List<String> binaries) async {
      final r = await Process.run('sh', [
        '-c',
        'set -eu\n${webBinaryTrustShell(binaries)}echo CHECK_PASSED',
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

    File exe(String path) {
      final f = File(path)..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['755', f.path]);
      return f;
    }

    test('a root-owned system binary passes', () async {
      final (rc, out) = await check(['/usr/bin/tail']);
      expect(rc, 0, reason: out);
      expect(out, contains('CHECK_PASSED'));
    }, skip: !Platform.isLinux);

    test('a clean root-owned file passes', () async {
      if (!isRoot) {
        markTestSkipped('needs root to own the temp file');
        return;
      }
      final f = exe('${dir.path}/nginx');
      final (rc, out) = await check([f.path, '/usr/bin/tail']);
      expect(rc, 0, reason: out);
      expect(out, contains('CHECK_PASSED'));
    });

    test('a group-writable file fails', () async {
      final f = exe('${dir.path}/nginx');
      Process.runSync('chmod', ['775', f.path]);
      final (rc, out) = await check(['/usr/bin/tail', f.path]);
      expect(rc, isNot(0));
      expect(out, isNot(contains('CHECK_PASSED')));
      expect(untrusted(out), f.path);
    }, skip: !Platform.isLinux);

    test('an other-writable file fails', () async {
      final f = exe('${dir.path}/nginx');
      Process.runSync('chmod', ['757', f.path]);
      final (rc, out) = await check([f.path]);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    }, skip: !Platform.isLinux);

    test('an other-writable directory fails', () async {
      final sub = Directory('${dir.path}/sbin')..createSync();
      final f = exe('${sub.path}/nginx');
      Process.runSync('chmod', ['777', sub.path]);
      final (rc, out) = await check([f.path]);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    }, skip: !Platform.isLinux);

    test('a writable parent further up fails', () async {
      final sub = Directory('${dir.path}/a/b')..createSync(recursive: true);
      final f = exe('${sub.path}/nginx');
      Process.runSync('chmod', ['775', '${dir.path}/a']);
      final (rc, out) = await check([f.path]);
      expect(rc, isNot(0));
      expect(untrusted(out), f.path);
    }, skip: !Platform.isLinux);

    test('a symlink to a writable target fails', () async {
      final bad = Directory('${dir.path}/bad')..createSync();
      final target = exe('${bad.path}/nginx');
      Process.runSync('chmod', ['777', bad.path]);
      final clean = Directory('${dir.path}/clean')..createSync();
      Process.runSync('chmod', ['755', clean.path]);
      final link = Link('${clean.path}/nginx')..createSync(target.path);
      final (rc, out) = await check([link.path]);
      expect(rc, isNot(0));
      expect(untrusted(out), link.path);
    }, skip: !Platform.isLinux);

    test('a missing binary fails', () async {
      final (rc, out) = await check(['${dir.path}/nope']);
      expect(rc, isNot(0));
      expect(untrusted(out), '${dir.path}/nope');
    }, skip: !Platform.isLinux);

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
