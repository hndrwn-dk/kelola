import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/probes/config_tested_reload_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/service_detect_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';

/// M52 architecture pins: the service lenses stay read-only (apart from the
/// two named mutating probes), never touch private keys, never sit behind the
/// billing gate, and never change the database schema.

/// `schemaVersion` on main when M52 started. M52 adds no Drift change.
const _schemaVersionWhenM52Started = 28;

HostFacts _facts(InitSystem init) => HostFacts(
  osId: 'ubuntu',
  osVersionId: '24.04',
  init: init,
  systemdVersion: init == InitSystem.systemd ? 255 : null,
  pkg: PackageManager.apt,
  fw: FirewallBackend.none,
  hasJournald: init == InitSystem.systemd,
  journalReadable: init == InitSystem.systemd,
  arch: 'x86_64',
);

final _allInits = [for (final i in InitSystem.values) _facts(i)];

String _read(String path) => File(path).readAsStringSync();

List<File> _dartFilesUnder(String dir) => [
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart')) e,
];

/// Every [WebLensProbe] variant: both servers, with and without detected
/// binaries and unit.
List<WebLensProbe> _webLensProbes() => const [
  WebLensProbe(id: ServiceId.nginx, binaries: {}),
  WebLensProbe(
    id: ServiceId.nginx,
    binaries: {'nginx': '/usr/sbin/nginx'},
    unit: 'nginx.service',
  ),
  WebLensProbe(id: ServiceId.apache, binaries: {}),
  WebLensProbe(
    id: ServiceId.apache,
    binaries: {'apachectl': '/usr/sbin/apachectl', 'httpd': '/usr/sbin/httpd'},
    unit: 'apache2.service',
  ),
  WebLensProbe(
    id: ServiceId.apache,
    binaries: {'httpd': '/usr/sbin/httpd'},
    unit: 'httpd',
  ),
];

List<ConfigTestedReloadProbe> _reloadProbes() => const [
  ConfigTestedReloadProbe(
    id: ServiceId.nginx,
    unit: 'nginx.service',
    testBin: '/usr/sbin/nginx',
  ),
  ConfigTestedReloadProbe(
    id: ServiceId.apache,
    unit: 'apache2.service',
    testBin: '/usr/sbin/apachectl',
  ),
];

/// The one place `sudo` is not an invocation: the shell condition from
/// [webSudoRefusedCondition] that recognises sudo's own refusal lines
/// (`[ "$rc" != 0 ] && { ! command -v sudo ... grep ... }`).
final _refusalCondition = RegExp(r'\[ "\$\w+" != 0 \] && \{[^\n]*\}');

/// [command] with the refusal conditions removed, so that every remaining
/// `sudo` is an invocation.
String _withoutSudoMentions(String command) =>
    command.replaceAll(_refusalCondition, '');

void _expectOnlySudoN(String command, String reason) {
  final stripped = _withoutSudoMentions(command);
  final bad = RegExp(r'(?<![A-Za-z])sudo(?! -n )').allMatches(stripped);
  expect(
    bad.map((m) => stripped.substring(m.start, m.start + 20)).toList(),
    isEmpty,
    reason: reason,
  );
}

void main() {
  group('probe risk and fleet gate', () {
    test(
      'ServiceDetectProbe and WebLensProbe are read, no sudo, fleet-safe',
      () {
        final probes = <Probe<dynamic>>[
          const ServiceDetectProbe(),
          ..._webLensProbes(),
        ];
        for (final p in probes) {
          final r = p.runtimeType.toString();
          expect(p.risk, RiskLevel.read, reason: r);
          expect(p.needsSudo, isFalse, reason: r);
          expect(
            () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
            returnsNormally,
            reason: r,
          );
        }
      },
    );

    test('ConfigTestedReloadProbe is mutate and blocked by the fleet gate', () {
      for (final p in _reloadProbes()) {
        expect(p.risk, RiskLevel.mutate);
        expect(
          () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
          throwsA(isA<FleetReadOnlyViolation>()),
        );
      }
    });

    test(
      'WebSudoersGrantProbe writes sudoers: mutate, blocked on the fleet',
      () {
        final grant = WebSudoersGrant.tryCreate(
          user: 'alice',
          id: ServiceId.nginx,
          binaries: const {'nginx': '/usr/sbin/nginx'},
        )!;
        final p = WebSudoersGrantProbe(grant);
        expect(p.risk, RiskLevel.mutate);
        expect(
          () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
          throwsA(isA<FleetReadOnlyViolation>()),
        );
      },
    );

    test('no probe in the feature is destructive', () {
      final grant = WebSudoersGrant.tryCreate(
        user: 'alice',
        id: ServiceId.apache,
        binaries: const {'apachectl': '/usr/sbin/apachectl'},
      )!;
      // The feature's probe classes, enumerated explicitly.
      final probes = <Probe<dynamic>>[
        const ServiceDetectProbe(),
        ..._webLensProbes(),
        ..._reloadProbes(),
        WebSudoersGrantProbe(grant),
      ];
      for (final p in probes) {
        expect(
          p.risk,
          isNot(RiskLevel.destructive),
          reason: '${p.runtimeType}',
        );
      }
    });
  });

  group('ConfigTestedReloadProbe command order', () {
    test('tests the config with -t and exits 3 before any reload', () {
      for (final p in _reloadProbes()) {
        for (final init in [InitSystem.systemd, InitSystem.openrc]) {
          final reason = '${p.id.name} ${init.name}';
          final cmd = p.command(_facts(init));
          final test = cmd.indexOf(' -t ');
          final guard = cmd.indexOf(r'[ "$rc" = 0 ] || exit 3');
          final reload = cmd.indexOf('reload');
          expect(test, greaterThan(-1), reason: reason);
          expect(guard, greaterThan(test), reason: reason);
          expect(reload, greaterThan(guard), reason: reason);
          // The reload text appears only after the guard, in one place.
          expect(
            cmd.substring(0, guard),
            isNot(contains('reload')),
            reason: reason,
          );
          expect(cmd, contains('exit 3'), reason: reason);
        }
      }
    });

    test('unsupported init and unsafe targets run nothing', () {
      for (final p in _reloadProbes()) {
        final cmd = p.command(_facts(InitSystem.unknown));
        expect(cmd, isNot(contains('reload')));
        expect(cmd, isNot(contains('sudo')));
      }
      const bad = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: r'nginx; rm -rf /',
        testBin: '/usr/sbin/nginx',
      );
      final cmd = bad.command(_facts(InitSystem.systemd));
      expect(cmd, isNot(contains('reload')));
      expect(cmd, isNot(contains('sudo')));
    });
  });

  group('commands never touch private keys or prompt for sudo', () {
    test('WebLensProbe never mentions a key path', () {
      for (final p in _webLensProbes()) {
        for (final facts in _allInits) {
          final cmd = p.command(facts);
          final reason = '${p.id.name} ${facts.init.name}';
          expect(cmd, isNot(contains('ssl_certificate_key')), reason: reason);
          expect(cmd, isNot(contains('SSLCertificateKeyFile')), reason: reason);
          expect(cmd, isNot(contains('.key')), reason: reason);
        }
      }
    });

    test('every sudo invocation is sudo -n', () {
      var seen = 0;
      for (final p in _webLensProbes()) {
        for (final facts in _allInits) {
          final cmd = p.command(facts);
          seen += 'sudo -n '.allMatches(cmd).length;
          _expectOnlySudoN(cmd, 'WebLensProbe ${p.id.name} ${facts.init.name}');
        }
      }
      for (final p in _reloadProbes()) {
        for (final init in [InitSystem.systemd, InitSystem.openrc]) {
          final cmd = p.command(_facts(init));
          seen += 'sudo -n '.allMatches(cmd).length;
          _expectOnlySudoN(cmd, 'Reload ${p.id.name} ${init.name}');
        }
      }
      // Guards the scan itself: it must actually have seen invocations.
      expect(seen, greaterThan(10));
    });
  });

  group('sudo grants', () {
    test('lines are exact-argv, root-only rules with no wildcards', () {
      final inputs = <List<Object?>>[
        [
          ServiceId.nginx,
          {'nginx': '/usr/sbin/nginx'},
          '/var/log/nginx/error.log',
          '/var/log/nginx/access.log',
        ],
        [
          ServiceId.apache,
          {'apachectl': '/usr/sbin/apachectl', 'httpd': '/usr/sbin/httpd'},
          '/var/log/apache2/error.log',
          '/var/log/apache2/access.log',
        ],
        [
          ServiceId.apache,
          {'httpd': '/usr/sbin/httpd'},
          '/var/log/httpd/error_log',
          '/var/log/httpd/access_log',
        ],
      ];
      for (final i in inputs) {
        final lines = webGrantLines(
          user: 'alice',
          id: i[0]! as ServiceId,
          binaries: i[1]! as Map<String, String>,
          toolPaths: const {
            'openssl': '/usr/bin/openssl',
            'tail': '/usr/bin/tail',
          },
          certPaths: const ['/etc/ssl/certs/site.pem'],
          errorLog: i[2] as String?,
          accessLog: i[3] as String?,
        );
        expect(lines.length, greaterThanOrEqualTo(5));
        for (final l in lines) {
          expect(l, startsWith('alice ALL=(root) NOPASSWD: /'));
          for (final c in const ['*', '^', '!', '?', '[']) {
            expect(l, isNot(contains(c)), reason: l);
          }
        }
      }
    });

    test('trust check owners are root everywhere in lib (test-only override unused)', () {
      final calls = <String>[];
      for (final f in _dartFilesUnder('lib')) {
        final src = f.readAsStringSync();
        // The override is never passed, to either entry point.
        expect(src, isNot(contains('owners:')), reason: f.path);
        expect(src, isNot(contains('trustOwners:')), reason: f.path);
        for (final m in RegExp(
          r'(webBinaryTrustShell|buildWebGrantScript)\(',
        ).allMatches(src)) {
          calls.add('${f.path}:${m.start}');
        }
      }
      expect(calls, isNotEmpty);
      final src = _read('lib/domain/sudo/web_sudoers_grant.dart');
      expect(
        src,
        contains(
          "@visibleForTesting List<String> owners = const ['root'],",
        ),
      );
      expect(
        src,
        contains(
          "@visibleForTesting List<String> trustOwners = const ['root'],",
        ),
      );
      // Production script: only root.
      final grant = WebSudoersGrant.tryCreate(
        user: 'alice',
        id: ServiceId.nginx,
        binaries: const {'nginx': '/usr/sbin/nginx'},
        toolPaths: const {'tail': '/usr/bin/tail'},
        errorLog: '/var/log/nginx/error.log',
      )!;
      expect(
        RegExp(r"-user '([^']*)'")
            .allMatches(buildWebGrantScript(grant))
            .map((m) => m.group(1))
            .toSet(),
        {'root'},
      );
    });

    test('path is the pinned kelola-web file', () {
      expect(kelolaWebSudoersPath, '/etc/sudoers.d/kelola-web');
    });

    test('no line for a binary outside the system directories', () {
      for (final dir in [
        '/usr/local/sbin',
        '/opt/nginx/sbin',
        '/tmp',
        '/home/a',
      ]) {
        expect(
          webGrantLines(
            user: 'alice',
            id: ServiceId.nginx,
            binaries: {'nginx': '$dir/nginx'},
          ),
          isEmpty,
          reason: dir,
        );
        expect(
          webGrantLines(
            user: 'alice',
            id: ServiceId.apache,
            binaries: {'apachectl': '$dir/apachectl'},
          ),
          isEmpty,
          reason: dir,
        );
      }
      // Tools outside the system dirs get no cert or log lines either.
      final lines = webGrantLines(
        user: 'alice',
        id: ServiceId.nginx,
        binaries: const {'nginx': '/usr/sbin/nginx'},
        toolPaths: const {
          'openssl': '/usr/local/bin/openssl',
          'tail': '/opt/bin/tail',
        },
        certPaths: const ['/etc/ssl/certs/site.pem'],
        errorLog: '/var/log/nginx/error.log',
        accessLog: '/var/log/nginx/access.log',
      );
      expect(
        lines.any((l) => l.contains('openssl') || l.contains('tail')),
        isFalse,
      );
      expect(webGrantSystemDirs, {'/usr/bin', '/usr/sbin', '/bin', '/sbin'});
    });
  });

  group('source-text pins', () {
    final gateFree = <String>[
      for (final f in _dartFilesUnder('lib/presentation/services')) f.path,
      'lib/presentation/screens/web_lens_screen.dart',
      'lib/presentation/fleet/fleet_service_filter.dart',
    ];

    test('lens UI is never behind the billing gate', () {
      expect(gateFree.length, greaterThanOrEqualTo(3));
      for (final path in gateFree) {
        final src = _read(path);
        expect(src, isNot(contains('ProFeature')), reason: path);
        expect(src, isNot(contains('isUnlocked')), reason: path);
      }
    });

    test('fleet_screen never references a lens probe', () {
      // Also pinned in fleet_tile_architecture_test.dart; kept here so the
      // M52 pins stand alone.
      final src = _read('lib/presentation/screens/fleet_screen.dart');
      for (final s in const [
        'WebLensProbe',
        'ServiceDetectProbe',
        'ConfigTestedReloadProbe',
      ]) {
        expect(src, isNot(contains(s)));
      }
    });

    test('lens screens use design-system components only', () {
      final paths = [
        'lib/presentation/screens/web_lens_screen.dart',
        for (final f in _dartFilesUnder('lib/presentation/services')) f.path,
      ];
      for (final path in paths) {
        final src = _read(path);
        for (final banned in const [
          'AlertDialog',
          'ListTile',
          ' Card(',
          'FloatingActionButton',
          'Color(0x',
        ]) {
          expect(src, isNot(contains(banned)), reason: '$path: $banned');
        }
      }
    });

    test('domain code does not import Flutter', () {
      final files = [
        ..._dartFilesUnder('lib/domain/services'),
        File('lib/domain/probes/service_detect_probe.dart'),
        File('lib/domain/probes/web_lens_probe.dart'),
        File('lib/domain/probes/config_tested_reload_probe.dart'),
      ];
      final designImporters = <String>[];
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('package:flutter/')), reason: f.path);
        expect(src, isNot(contains('dart:ui')), reason: f.path);
        if (src.contains("package:kelola/design/")) designImporters.add(f.path);
      }
      // The only design import is web_lens.dart's HealthStatus (kelola_theme).
      expect(designImporters, ['lib/domain/services/web_lens.dart']);
      expect(
        _read('lib/domain/services/web_lens.dart'),
        contains("import 'package:kelola/design/kelola_theme.dart';"),
      );
    });
  });

  group('no schema or entitlement change', () {
    test('Drift schemaVersion is unchanged by M52', () {
      expect(
        _read('lib/data/db/database.dart'),
        contains('int get schemaVersion => $_schemaVersionWhenM52Started;'),
      );
    });

    test('ProFeature gains no value', () {
      final src = _read('packages/kelola_pro/lib/src/pro_feature.dart');
      expect(
        src.replaceAll(RegExp(r'\s+'), ' '),
        contains(
          'enum ProFeature { tunnels, fleetUnlimited, snippetMulti, vaultSync }',
        ),
      );
      expect(RegExp(r'\benum\b').allMatches(src).length, 1);
    });
  });
}
