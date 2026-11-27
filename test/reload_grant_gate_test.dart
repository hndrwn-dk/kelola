import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/support/support_links.dart';

// PR #3 gated the web lens config test (`-t`) on a root-controlled config.
// A start, restart or reload of the web server as root loads the same config
// and modules, so the lifecycle lines Kelola writes for a web server unit get
// the same host-side check, and a failure drops that unit's lines only.

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

const _nginx = DetectedService(
  id: ServiceId.nginx,
  state: ServiceState.running,
  unit: 'nginx.service',
  binaries: {'nginx': '/usr/sbin/nginx'},
);

const _apache = DetectedService(
  id: ServiceId.apache,
  state: ServiceState.running,
  unit: 'apache2.service',
  binaries: {'apachectl': '/usr/sbin/apachectl'},
);

const _mariadb = DetectedService(
  id: ServiceId.mariadb,
  state: ServiceState.running,
  unit: 'mariadb.service',
);

const _p = 'hendr ALL=(root) NOPASSWD: ';

List<String> _unitLines(String unit) => [
  for (final v in kelolaUnitLifecycleVerbs) '$_p/usr/bin/systemctl $v $unit',
];

KelolaSudoersSpec _exactSpec(List<String> units) => buildKelolaSudoersSpec(
  user: 'hendr',
  facts: _facts,
  groups: defaultKelolaSudoersGroups(
    _facts,
    sudo: const SudoRs('0.2.13'),
    units: units,
  ),
  sudo: const SudoRs('0.2.13'),
  units: units,
);

void main() {
  group('which units are web servers', () {
    test('nginx and Apache units, with or without .service', () {
      expect(webServerForUnit('nginx.service'), ServiceId.nginx);
      expect(webServerForUnit('nginx'), ServiceId.nginx);
      expect(webServerForUnit('apache2.service'), ServiceId.apache);
      expect(webServerForUnit('httpd.service'), ServiceId.apache);
      expect(webServerForUnit('httpd'), ServiceId.apache);
    });

    test('anything else is not', () {
      for (final u in [
        'mariadb.service',
        'nginx-exporter.service',
        'mynginx.service',
        'sshd.service',
        '',
      ]) {
        expect(webServerForUnit(u), isNull, reason: u);
      }
    });

    test('gates come from host web services and the unit that asked', () {
      final gates = webUnitGatesFor(
        services: const [_nginx, _mariadb, _apache],
        hintUnit: 'mariadb.service',
      );
      expect(gates.map((g) => g.unit), ['nginx.service', 'apache2.service']);
      expect(gates.first.id, ServiceId.nginx);
      expect(gates.first.binary, '/usr/sbin/nginx');
      expect(gates.last.binary, '/usr/sbin/apachectl');
    });

    test('a web hint unit with no detected service has no binary', () {
      final gates = webUnitGatesFor(services: const [], hintUnit: 'nginx');
      expect(gates.single.unit, 'nginx');
      expect(gates.single.binary, isNull);
    });

    test('container services and unsafe names are skipped', () {
      final gates = webUnitGatesFor(
        services: const [
          DetectedService(
            id: ServiceId.nginx,
            state: ServiceState.running,
            unit: 'nginx.service',
            container: 'web',
          ),
          DetectedService(
            id: ServiceId.apache,
            state: ServiceState.running,
            unit: r'apache2.service;id',
          ),
        ],
      );
      expect(gates, isEmpty);
    });
  });

  group('install script', () {
    test(
      'hosts without web units keep the pre-change script byte for byte',
      () {
        final snap = (jsonDecode(
          File('test/fixtures/sudoers/install_script_no_web_units.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>).cast<String, String>();
        const units = ['mariadb.service', 'redis-server.service'];
        for (final e in <String, SudoFlavor>{
          'classic-1.9.15': const ClassicSudo(1, 9, 15),
          'sudo-rs': const SudoRs('0.2.13'),
        }.entries) {
          const facts = HostFacts(
            osId: 'x',
            osVersionId: '1',
            init: InitSystem.systemd,
            systemdVersion: 252,
            pkg: PackageManager.apt,
            fw: FirewallBackend.ufw,
            hasJournald: true,
            journalReadable: true,
            arch: 'x86_64',
          );
          final spec = buildKelolaSudoersSpec(
            user: 'hendr',
            facts: facts,
            groups: defaultKelolaSudoersGroups(
              facts,
              sudo: e.value,
              units: units,
            ),
            sudo: e.value,
            units: units,
          );
          // No web gate for a non-web unit: unchanged.
          final gates = webUnitGatesFor(
            services: const [_mariadb],
            hintUnit: 'redis-server.service',
          );
          expect(gates, isEmpty);
          expect(
            buildSudoersInstallScript(
              content: spec.content,
              user: 'hendr',
              webUnitGates: gates,
            ),
            snap['${e.key}/plain'],
          );
          expect(
            buildSudoersInstallScript(
              content: spec.content,
              user: 'hendr',
              retireUnits: true,
              journalGroup: true,
              webUnitGates: gates,
            ),
            snap['${e.key}/retire+journal'],
          );
        }
      },
    );

    test('a web unit gate runs the config check before visudo', () {
      final spec = _exactSpec(['nginx.service']);
      final s = buildSudoersInstallScript(
        content: spec.content,
        user: 'hendr',
        webUnitGates: webUnitGatesFor(services: const [_nginx]),
      );
      expect(s, contains('kelola_cfg'));
      expect(s.indexOf('kelola_cfg'), lessThan(s.indexOf('visudo -c')));
      expect(s, contains(sudoersUnitConfigMarker));
      // The unit and its lines travel base64, never as shell text.
      expect(s, isNot(contains('systemctl reload nginx.service')));
    });

    test('nginx with no known binary fails closed in the script', () {
      final spec = _exactSpec(['nginx']);
      final s = buildSudoersInstallScript(
        content: spec.content,
        user: 'hendr',
        webUnitGates: webUnitGatesFor(services: const [], hintUnit: 'nginx'),
      );
      expect(s, contains(sudoersUnitConfigMarker));
      expect(s, isNot(contains(' -V ')));
    });
  });

  group('install result', () {
    String b64(String s) => base64Encode(utf8.encode(s));

    test('a refused unit: its lines are left out, the rest verify', () {
      final spec = _exactSpec(['nginx.service', 'mariadb.service']);
      final gates = webUnitGatesFor(services: const [_nginx]);
      final kept = [
        for (final l in spec.content.split('\n'))
          if (!_unitLines('nginx.service').contains(l)) l,
      ].join('\n');
      final out =
          '$sudoersUnitConfigMarker ${b64('nginx.service')} '
          '${b64('/etc/nginx/sites-enabled')} mode\n'
          '$kept\n$sudoersInstallOkMarker\n';
      final r = parseSudoersInstallOutput(
        stdout: out,
        stderr: '',
        exitCode: 0,
        expectedContent: spec.content,
        user: 'hendr',
        webUnitGates: gates,
      );
      expect(r.ok, isTrue, reason: r.errorSummary);
      expect(r.unitRefusals, hasLength(1));
      expect(r.unitRefusals.single.unit, 'nginx.service');
      expect(r.unitRefusals.single.refusal.path, '/etc/nginx/sites-enabled');
      expect(r.unitRefusals.single.refusal.reason, WebConfigRefusalReason.mode);
      expect(
        webUnitRefusalCopy(r.unitRefusals.single),
        'nginx.service start, stop, restart and reload not granted: '
        '/etc/nginx/sites-enabled is writable by group or others.',
      );
    });

    test('an unknown nginx binary reads as such', () {
      final spec = _exactSpec(['nginx']);
      final gates = webUnitGatesFor(services: const [], hintUnit: 'nginx');
      final kept = [
        for (final l in spec.content.split('\n'))
          if (!_unitLines('nginx').contains(l)) l,
      ].join('\n');
      final r = parseSudoersInstallOutput(
        stdout:
            '$sudoersUnitConfigMarker ${b64('nginx')} - unreadable\n'
            '$kept\n$sudoersInstallOkMarker\n',
        stderr: '',
        exitCode: 0,
        expectedContent: spec.content,
        user: 'hendr',
        webUnitGates: gates,
      );
      expect(r.ok, isTrue, reason: r.errorSummary);
      expect(
        webUnitRefusalCopy(r.unitRefusals.single),
        'nginx start, stop, restart and reload not granted: the server '
        'binary could not be checked.',
      );
    });

    test('a refusal for a unit that was not gated is ignored', () {
      final spec = _exactSpec(['mariadb.service']);
      final out =
          '$sudoersUnitConfigMarker ${b64('nginx.service')} '
          '${b64('/etc/nginx')} owner\n'
          '${spec.content}\n$sudoersInstallOkMarker\n';
      final r = parseSudoersInstallOutput(
        stdout: out,
        stderr: '',
        exitCode: 0,
        expectedContent: spec.content,
        user: 'hendr',
      );
      expect(r.ok, isTrue);
      expect(r.unitRefusals, isEmpty);
    });

    test('lines missing without a refusal still fail the verify', () {
      final spec = _exactSpec(['nginx.service']);
      final kept = [
        for (final l in spec.content.split('\n'))
          if (!_unitLines('nginx.service').contains(l)) l,
      ].join('\n');
      final r = parseSudoersInstallOutput(
        stdout: '$kept\n$sudoersInstallOkMarker\n',
        stderr: '',
        exitCode: 0,
        expectedContent: spec.content,
        user: 'hendr',
        webUnitGates: webUnitGatesFor(services: const [_nginx]),
      );
      expect(r.ok, isFalse);
    });
  });

  group('services regex rule note', () {
    test('Enable sheet and help topic carry the same line', () {
      expect(
        kelolaServicesConfigAsRootNote,
        "Passwordless service restart runs that service's config as root. "
        'Only enable it where service configs are root-owned.',
      );
      final faq = kSupportFaq.firstWhere(
        (f) => f.question == 'Why does an action say sudo needs a password?',
      );
      expect(faq.answer, contains(kelolaServicesConfigAsRootNote));
    });
  });

  group('outdated config-test grant', () {
    test('a listed -t line for this server is found', () {
      final listed = parseSudoListing(
        'User hendr may run the following commands on h:\n'
        '    (root) NOPASSWD: /usr/sbin/nginx -t\n'
        '    (root) NOPASSWD: /usr/sbin/nginx -T\n'
        '    (root) NOPASSWD: /usr/bin/tail -n 60 /var/log/nginx/error.log\n'
        '    (root) NOPASSWD: /usr/sbin/apachectl -t\n',
      );
      expect(webListedConfigTestLines(listed: listed, id: ServiceId.nginx), [
        '/usr/sbin/nginx -t',
        '/usr/sbin/nginx -T',
      ]);
      expect(webListedConfigTestLines(listed: listed, id: ServiceId.apache), [
        '/usr/sbin/apachectl -t',
      ]);
    });

    test('no -t line, nothing outdated', () {
      final listed = parseSudoListing(
        '    (root) NOPASSWD: /usr/bin/tail -n 60 /var/log/nginx/error.log\n'
        '    (root) NOPASSWD: /usr/local/sbin/nginx -t\n',
      );
      expect(
        webListedConfigTestLines(listed: listed, id: ServiceId.nginx),
        isEmpty,
      );
    });

    test('the trust probe reports a refusal or a pass', () {
      final probe = WebConfigTrustProbe(
        id: ServiceId.nginx,
        binary: '/usr/sbin/nginx',
      );
      expect(probe.risk.name, 'read');
      expect(probe.needsSudo, isFalse);
      expect(probe.command(_facts), isNot(contains('sudo')));
      expect(probe.parse('$webConfigTrustOkMarker\n', '', 0), isNull);
      final r = probe.parse(
        '$webGrantConfigMarker ${base64Encode(utf8.encode('/etc/nginx/conf.d'))} owner\n',
        '',
        0,
      );
      expect(r!.path, '/etc/nginx/conf.d');
      expect(r.reason, WebConfigRefusalReason.owner);
      // No verdict either way: nothing is shown.
      expect(probe.parse('', '', 1), isNull);
    });
  });

  _realTrees();
}

/// Runs the install script against stub trees, under dash and under busybox
/// sh, like the web grant's config gate tests. Linux only.
void _realTrees() {
  final me = Platform.isWindows
      ? ''
      : (Process.runSync('id', ['-un']).stdout as String).trim();
  final isRoot = me == 'root';
  final owners = {'root', me}.toList();
  final hasDash =
      !Platform.isWindows &&
      Process.runSync('sh', ['-c', 'command -v dash']).exitCode == 0;

  group('web unit gate (real trees)', skip: Platform.isWindows, () {
    String? bbDir;
    Directory? base;
    late Directory root;
    late Directory bin;
    late File kelola;
    late File units;

    setUpAll(() {
      final which = Process.runSync('sh', ['-c', 'command -v busybox']);
      final bb = (which.stdout as String).trim();
      if (which.exitCode == 0 && bb.isNotEmpty) {
        final d = Directory.systemTemp.createTempSync('kelola_bb');
        final r = Process.runSync(bb, ['--install', '-s', d.path]);
        if (r.exitCode == 0 && File('${d.path}/find').existsSync()) {
          bbDir = d.path;
        } else {
          d.deleteSync(recursive: true);
        }
      }
      // A directory whose owner chain is clean for [owners] (/tmp never is).
      for (final p in [
        '${Directory.current.path}/.dart_tool',
        Platform.environment['HOME'] ?? '',
      ]) {
        if (p.isEmpty || !Directory(p).existsSync()) continue;
        final s = webBinaryTrustShell([p], owners: owners);
        final r = Process.runSync('sh', ['-c', 'set -eu\n${s}echo OK']);
        if (r.exitCode == 0) {
          base = Directory(p);
          break;
        }
      }
    });

    tearDownAll(() {
      final d = bbDir;
      if (d != null) Directory(d).deleteSync(recursive: true);
    });

    setUp(() {
      final b = base;
      if (b == null) return;
      root = b.createTempSync('kelola_unitgate');
      Process.runSync('chmod', ['755', root.path]);
      bin = Directory.systemTemp.createTempSync('kelola_unitgate_bin');
      kelola = File('${bin.path}/kelola');
      units = File('${bin.path}/kelola-units');
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
  [ "\$a" = $kelolaSudoersPath ] && a=${kelola.path}
  [ "\$a" = $kelolaUnitSudoersPath ] && a=${units.path}
  set -- "\$@" "\$a"
done
exec "\$@"''');
      stub('visudo', 'exit 0');
      stub('install', '''
eval "src=\\\${\$((\$# - 1))}"
eval "dst=\\\${\$#}"
cp "\$src" "\$dst"''');
    });

    tearDown(() {
      if (base == null) return;
      Process.runSync('chmod', ['-R', 'u+rwx', root.path]);
      root.deleteSync(recursive: true);
      bin.deleteSync(recursive: true);
    });

    Directory sub(String name, {String mode = '755'}) {
      final d = Directory('${root.path}/$name')..createSync(recursive: true);
      Process.runSync('chmod', [mode, d.path]);
      return d;
    }

    File file(String path, {String mode = '644', String body = ''}) {
      final f = File(path)..writeAsStringSync(body);
      Process.runSync('chmod', [mode, f.path]);
      return f;
    }

    /// A Debian-like nginx tree and a stub nginx whose `-V` names it.
    ({String stub, Directory conf}) nginxTree() {
      final conf = sub('etc/nginx');
      file('${conf.path}/nginx.conf', body: 'events {}\n');
      file('${conf.path}/mime.types');
      sub('etc/nginx/conf.d');
      file('${sub('etc/nginx/sites-enabled').path}/default');
      final stub = file(
        '${sub('sbin').path}/nginx',
        mode: '755',
        body:
            '#!/bin/sh\n'
            '[ "\$1" = -V ] || exit 1\n'
            'echo "nginx version: nginx/1.24.0" >&2\n'
            'echo "configure arguments: --prefix=${root.path}/usr/share/nginx '
            '--conf-path=${conf.path}/nginx.conf" >&2\n',
      ).path;
      return (stub: stub, conf: conf);
    }

    String b64(String s) => base64Encode(utf8.encode(s));

    String script(
      KelolaSudoersSpec spec,
      List<WebUnitGate> gates, {
      String? nginxStub,
      bool retire = false,
    }) {
      var s = buildSudoersInstallScript(
        content: spec.content,
        user: 'hendr',
        retireUnits: retire,
        webUnitGates: gates,
        trustOwners: owners,
        configPrefix: root.path,
      );
      if (nginxStub != null) {
        expect(s, contains("'${b64('/usr/sbin/nginx')}'"));
        s = s.replaceAll("'${b64('/usr/sbin/nginx')}'", "'${b64(nginxStub)}'");
      }
      return s;
    }

    Future<ProcessResult> run(String s, String shell) async {
      final path = shell == 'busybox'
          ? '${bin.path}:$bbDir'
          : '${bin.path}:/usr/bin:/bin';
      final argv = shell == 'busybox'
          ? ['busybox', 'sh', '-c', s]
          : ['dash', '-c', s];
      final p = await Process.start('env', ['PATH=$path', ...argv]);
      p.stdin.write('pw\n');
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final err = await p.stderr.transform(utf8.decoder).join();
      return ProcessResult(p.pid, await p.exitCode, out, err);
    }

    bool go(String shell) {
      if (base == null) {
        markTestSkipped('no directory with a clean owner chain here');
        return false;
      }
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

    SudoersInstallResult parse(
      ProcessResult r,
      KelolaSudoersSpec spec,
      List<WebUnitGate> gates,
    ) => parseSudoersInstallOutput(
      stdout: r.stdout as String,
      stderr: r.stderr as String,
      exitCode: r.exitCode,
      expectedContent: spec.content,
      user: 'hendr',
      webUnitGates: gates,
    );

    for (final shell in const ['dash', 'busybox']) {
      test('$shell: a trusted tree keeps the nginx reload line', () async {
        if (!go(shell)) return;
        final t = nginxTree();
        final spec = _exactSpec(['nginx.service', 'mariadb.service']);
        final gates = webUnitGatesFor(services: const [_nginx]);
        final r = await run(script(spec, gates, nginxStub: t.stub), shell);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(r.stdout, isNot(contains(sudoersUnitConfigMarker)));
        expect(kelola.readAsStringSync(), spec.content);
        final res = parse(r, spec, gates);
        expect(res.ok, isTrue, reason: res.errorSummary);
        expect(res.unitRefusals, isEmpty);
      });

      test(
        '$shell: a group-writable sites-enabled drops the nginx lines, with the path',
        () async {
          if (!go(shell)) return;
          final t = nginxTree();
          Process.runSync('chmod', ['775', '${t.conf.path}/sites-enabled']);
          final spec = _exactSpec(['nginx.service', 'mariadb.service']);
          final gates = webUnitGatesFor(services: const [_nginx]);
          final r = await run(script(spec, gates, nginxStub: t.stub), shell);
          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          final written = kelola.readAsLinesSync();
          for (final l in _unitLines('nginx.service')) {
            expect(written, isNot(contains(l)));
          }
          for (final l in _unitLines('mariadb.service')) {
            expect(written, contains(l));
          }
          final res = parse(r, spec, gates);
          expect(res.ok, isTrue, reason: '${res.errorSummary} ${r.stdout}');
          expect(res.unitRefusals.single.unit, 'nginx.service');
          expect(
            res.unitRefusals.single.refusal.path,
            '${t.conf.path}/sites-enabled',
          );
          expect(
            res.unitRefusals.single.refusal.reason,
            WebConfigRefusalReason.mode,
          );
        },
      );

      test('$shell: a non-web unit runs no check', () async {
        if (!go(shell)) return;
        final spec = _exactSpec(['mariadb.service']);
        final gates = webUnitGatesFor(services: const [_mariadb]);
        expect(gates, isEmpty);
        final s = script(spec, gates);
        expect(s, isNot(contains('kelola_cfg')));
        final r = await run(s, shell);
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
        expect(kelola.readAsStringSync(), spec.content);
      });

      test(
        '$shell: folded Enable for nginx on a writable tree drops that unit only',
        () async {
          if (!go(shell)) return;
          final t = nginxTree();
          if (isRoot) {
            Process.runSync('chown', ['nobody', '${t.conf.path}/conf.d']);
          } else {
            Process.runSync('chmod', ['g+w', '${t.conf.path}/conf.d']);
          }
          // Regex-tier host: no exact lines; the old per-unit grant had two.
          final spec = buildKelolaSudoersSpec(
            user: 'hendr',
            facts: _facts,
            groups: {KelolaSudoersGroup.services},
            sudo: const ClassicSudo(1, 9, 15),
          );
          units.writeAsStringSync(
            '$_p/usr/bin/systemctl reload nginx.service\n'
            '$_p/usr/bin/systemctl restart mariadb.service\n',
          );
          final gates = webUnitGatesFor(services: const [_nginx, _mariadb]);
          final r = await run(
            script(spec, gates, nginxStub: t.stub, retire: true),
            shell,
          );
          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          final written = kelola.readAsLinesSync();
          expect(
            written,
            isNot(contains('$_p/usr/bin/systemctl reload nginx.service')),
          );
          expect(
            written,
            contains('$_p/usr/bin/systemctl restart mariadb.service'),
          );
          // Every line was handled (moved or dropped), so the old file goes.
          expect(r.stdout, contains(sudoersUnitsRetiredMarker));
          expect(units.existsSync(), isFalse);
          final res = parse(r, spec, gates);
          expect(res.ok, isTrue, reason: '${res.errorSummary} ${r.stdout}');
          expect(res.unitRefusals.single.unit, 'nginx.service');
          expect(res.unitRefusals.single.refusal.path, '${t.conf.path}/conf.d');
        },
      );
    }
  });
}
