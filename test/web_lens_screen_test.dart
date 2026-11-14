import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/app.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/data/keystore/hardware_signer.dart';
import 'package:kelola/data/ssh/host_key_policy.dart';
import 'package:kelola/data/ssh/session_pool.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/files/sftp_port.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/probes/config_tested_reload_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/sudo_flavor_probe.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';
import 'package:kelola/domain/services/web_lens.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/presentation/screens/web_lens_screen.dart';
import 'package:kelola/providers.dart';

const _nginx = DetectedService(
  id: ServiceId.nginx,
  state: ServiceState.running,
  unit: 'nginx.service',
  version: '1.24.0',
  binaries: {'nginx': '/usr/sbin/nginx'},
);

HostFacts _facts() => const HostFacts(
      osId: 'ubuntu',
      osVersionId: '24.04',
      prettyName: 'Ubuntu 24.04',
      init: InitSystem.systemd,
      systemdVersion: 255,
      pkg: PackageManager.apt,
      fw: FirewallBackend.none,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
    );

const _shop = WebVhost(
  serverNames: ['shop.example.com', 'www.shop.example.com'],
  listen: ['443 ssl', '[::]:443 ssl'],
  tls: true,
  root: '/var/www/shop',
  certPath: '/etc/ssl/certs/shop.crt',
  certPaths: ['/etc/ssl/certs/shop.crt'],
  sourceFile: '/etc/nginx/conf.d/shop.conf',
);
const _api = WebVhost(
  serverNames: ['api.example.com'],
  listen: ['443 ssl'],
  tls: true,
  certPath: '/etc/ssl/certs/api.crt',
  certPaths: ['/etc/ssl/certs/api.crt'],
  sourceFile: '/etc/nginx/conf.d/api.conf',
);
const _blog = WebVhost(
  serverNames: ['blog.example.com'],
  listen: ['443 ssl'],
  tls: true,
  certPath: '/etc/ssl/certs/blog.crt',
  certPaths: ['/etc/ssl/certs/blog.crt'],
  sourceFile: '/etc/nginx/conf.d/blog.conf',
);
const _plain = WebVhost(
  serverNames: ['_'],
  listen: ['80 default_server'],
  root: '/var/www/html',
  sourceFile: '/etc/nginx/sites-enabled/default',
);

/// 4 vhosts: 3 TLS, one cert (shop) expiring in 10 days, 1 without TLS.
WebLens _lens({
  DateTime? readAt,
  bool? configOk = true,
  List<WebVhost> vhosts = const [_shop, _api, _blog, _plain],
  Map<String, WebCert>? certs,
  Map<int, int> statusCounts = const {200: 900, 301: 40, 404: 56, 502: 4},
  Map<WebLensSection, String> sectionErrors = const {},
  WebLogStat? errorLogStat,
  WebLogStat? accessLogStat,
  List<String>? loginGroups,
  List<String> errorLogTail = const [
    '2026/11/10 01:31:42 [error] 3159#3159: *1 connect() failed (111: Connection refused) while connecting to upstream',
    '2026/11/10 01:31:48 [warn] 3176#3176: *2 an upstream response is buffered to a temporary file',
    '2026/11/10 01:31:53 [notice] 3190#3190: signal process started',
  ],
}) {
  final at = readAt ?? DateTime.now().toUtc();
  return WebLens(
    id: ServiceId.nginx,
    readAt: at,
    activeState: 'active',
    configOk: configOk,
    vhosts: vhosts,
    certsByPath: certs ??
        {
          '/etc/ssl/certs/shop.crt': WebCert(
            path: '/etc/ssl/certs/shop.crt',
            notAfter: at.add(const Duration(days: 10, hours: 2)),
            subjectCn: 'shop.example.com',
            sans: const ['shop.example.com', 'www.shop.example.com'],
          ),
          '/etc/ssl/certs/api.crt': WebCert(
            path: '/etc/ssl/certs/api.crt',
            notAfter: at.add(const Duration(days: 80)),
            subjectCn: 'api.example.com',
            sans: const ['api.example.com'],
          ),
          '/etc/ssl/certs/blog.crt': WebCert(
            path: '/etc/ssl/certs/blog.crt',
            notAfter: at.add(const Duration(days: 60)),
            subjectCn: 'blog.example.com',
            sans: const ['blog.example.com'],
          ),
        },
    errorLogTail: errorLogTail,
    statusCounts: statusCounts,
    sectionErrors: sectionErrors,
    errorLogStat: errorLogStat,
    accessLogStat: accessLogStat,
    loginGroups: loginGroups,
  );
}

/// Same, but every cert is far from expiry.
WebLens _healthyLens({bool? configOk = true}) {
  final at = DateTime.now().toUtc();
  return _lens(
    readAt: at,
    configOk: configOk,
    certs: {
      for (final p in [
        '/etc/ssl/certs/shop.crt',
        '/etc/ssl/certs/api.crt',
        '/etc/ssl/certs/blog.crt',
      ])
        p: WebCert(path: p, notAfter: at.add(const Duration(days: 90))),
    },
  );
}

void main() {
  group('filterVhosts', () {
    test('all / tls / expiring / noTls', () {
      final l = _lens();
      final now = l.readAt;
      expect(filterVhosts(l, VhostFilter.all, now), hasLength(4));
      expect(filterVhosts(l, VhostFilter.tls, now), [_shop, _api, _blog]);
      expect(filterVhosts(l, VhostFilter.expiring, now), [_shop]);
      expect(filterVhosts(l, VhostFilter.noTls, now), [_plain]);
    });

    test('expired counts as expiring; unreadable does not', () {
      final at = DateTime.now().toUtc();
      final l = _lens(
        readAt: at,
        certs: {
          '/etc/ssl/certs/shop.crt': WebCert(
            path: '/etc/ssl/certs/shop.crt',
            notAfter: at.subtract(const Duration(days: 3)),
          ),
          '/etc/ssl/certs/api.crt':
              const WebCert(path: '/etc/ssl/certs/api.crt'),
        },
      );
      expect(filterVhosts(l, VhostFilter.expiring, at), [_shop]);
    });
  });

  group('band', () {
    test('headline is the first failed finding even when a warning is first',
        () {
      const warn = WebFinding(
        kind: WebFindingKind.certExpiring,
        level: WebFindingLevel.warning,
        message: 'Certificate expires in 12 days',
        subject: 'a.example.com',
      );
      const fact = WebFinding(
        kind: WebFindingKind.defaultVhostOnly,
        level: WebFindingLevel.fact,
        message: 'Default vhost only',
      );
      const failed = WebFinding(
        kind: WebFindingKind.certExpired,
        level: WebFindingLevel.failed,
        message: 'Certificate expired',
        subject: 'b.example.com',
      );
      expect(bandFindings(const [warn, fact, failed]), [failed, warn]);
      expect(bandFindings(const [fact, warn]), [warn]);
      expect(bandFindings(const [fact]), isEmpty);
    });

    test('web5xxFires uses the finding kind', () {
      const fires = WebFinding(
        kind: WebFindingKind.http5xx,
        level: WebFindingLevel.warning,
        message: 'anything',
      );
      const other = WebFinding(
        kind: WebFindingKind.certExpiring,
        level: WebFindingLevel.warning,
        message: '5xx lookalike copy',
      );
      expect(web5xxFires(const [fires]), isTrue);
      expect(web5xxFires(const [other]), isFalse);
    });
  });

  group('webErrorLogLine', () {
    test('nginx line', () {
      final p = webErrorLogLine(
        '2026/11/10 01:31:42 [warn] 3176#3176: *2 buffered',
      );
      expect(p.timestamp, '2026/11/10 01:31:42');
      expect(p.kind, JournalLineKind.warning);
      expect(p.message, '3176#3176: *2 buffered');
    });

    test('apache line', () {
      final p = webErrorLogLine(
        '[Tue Nov 10 01:31:42.123456 2026] [core:error] [pid 1234] '
        'AH00037: Symbolic link not allowed',
      );
      expect(p.timestamp, 'Tue Nov 10 01:31:42.123456 2026');
      expect(p.kind, JournalLineKind.error);
      expect(p.message, '[pid 1234] AH00037: Symbolic link not allowed');
      expect(
        webErrorLogLine('[Tue Nov 10 01:31:42 2026] [ssl:warn] [pid 9] x').kind,
        JournalLineKind.warning,
      );
      expect(
        webErrorLogLine('[Tue Nov 10 01:31:42 2026] [mpm_event:notice] x').kind,
        JournalLineKind.info,
      );
    });

    test('unknown shape is the whole line as info', () {
      final p = webErrorLogLine('junk without a timestamp');
      expect(p.timestamp, '');
      expect(p.message, 'junk without a timestamp');
      expect(p.kind, JournalLineKind.info);
    });
  });

  // Fix 2: the adm group hint (pure).
  group('webAdmHintSection', () {
    const err = 'Could not read error log: no access with or without sudo -n';
    const acc = 'Could not read access log: no access with or without sudo -n';
    const adm = WebLogStat(owner: 'www-data', group: 'adm', mode: '640');

    WebLens l({
      Map<WebLensSection, String> errors = const {
        WebLensSection.errorLog: err,
        WebLensSection.access: acc,
      },
      WebLogStat? errStat = adm,
      WebLogStat? accStat,
      List<String>? groups = const ['deploy', 'sudo'],
    }) =>
        _lens(
          sectionErrors: errors,
          errorLogStat: errStat,
          accessLogStat: accStat,
          loginGroups: groups,
        );

    test('matching error log', () {
      expect(webAdmHintSection(user: 'deploy', lens: l()),
          WebLensSection.errorLog);
    });

    test('both logs match: one hint, at the error log', () {
      expect(webAdmHintSection(user: 'deploy', lens: l(accStat: adm)),
          WebLensSection.errorLog);
    });

    test('only the access log matches', () {
      expect(
        webAdmHintSection(
          user: 'deploy',
          lens: l(
            errStat: const WebLogStat(owner: 'root', group: 'root', mode: '600'),
            accStat: adm,
          ),
        ),
        WebLensSection.access,
      );
      // The error log read fine: its stat alone is no reason.
      expect(
        webAdmHintSection(
          user: 'deploy',
          lens: l(errors: const {WebLensSection.access: acc}, accStat: null),
        ),
        isNull,
      );
    });

    test('no hint unless every condition holds', () {
      for (final (name, lens, user) in [
        ('no section error', l(errors: const {}), 'deploy'),
        ('stat unknown', l(errStat: null), 'deploy'),
        (
          'group nginx (Alpine)',
          l(errStat: const WebLogStat(owner: 'nginx', group: 'nginx', mode: '640')),
          'deploy',
        ),
        (
          'no group read',
          l(errStat: const WebLogStat(owner: 'root', group: 'adm', mode: '600')),
          'deploy',
        ),
        ('groups unknown', l(groups: null), 'deploy'),
        ('already in adm', l(groups: const ['deploy', 'adm']), 'deploy'),
        ('unsafe user', l(), 'bad user'),
        ('unsafe user', l(), r'x$(id)'),
        ('ALL', l(), 'ALL'),
        ('empty user', l(), ''),
      ]) {
        expect(webAdmHintSection(user: user, lens: lens), isNull, reason: name);
      }
    });

    test('group read bit', () {
      expect(const WebLogStat(owner: 'a', group: 'adm', mode: '640').groupReadable, isTrue);
      expect(const WebLogStat(owner: 'a', group: 'adm', mode: '0644').groupReadable, isTrue);
      expect(const WebLogStat(owner: 'a', group: 'adm', mode: '2750').groupReadable, isTrue);
      expect(const WebLogStat(owner: 'a', group: 'adm', mode: '604').groupReadable, isFalse);
      expect(const WebLogStat(owner: 'a', group: 'adm', mode: '630').groupReadable, isFalse);
    });

    test('command text', () {
      expect(webAdmUsermodCommand('deploy'), 'sudo usermod -aG adm deploy');
    });
  });

  group('screen', () {
    late KelolaDatabase db;
    late HostRepository repo;
    late _Pool pool;
    late Host host;

    setUp(() async {
      db = KelolaDatabase.memory();
      repo = HostRepository(db);
      pool = _Pool(repository: repo);
      host = await repo.insert(
        alias: 'web01',
        address: '192.168.1.10',
        port: 22,
        username: 'hendra',
      );
      await repo.saveFacts(host.id, _facts());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> frames(WidgetTester tester, [int n = 12]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpLens(
      WidgetTester tester, {
      DetectedService service = _nginx,
    }) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            hostRepositoryProvider.overrideWithValue(repo),
            sessionPoolProvider.overrideWithValue(pool),
            hardwareSignerProvider.overrideWithValue(_BoomSigner()),
            enrollmentProvider.overrideWith(_ReadyEnrollment.new),
          ],
          child: KelolaApp(
            home: WebLensScreen(hostId: host.id, service: service),
          ),
        ),
      );
      await frames(tester);
    }

    Future<void> dispose(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }

    Finder vhostRow(String name) => find.widgetWithText(ServiceRow, name);

    StatCard card(WidgetTester tester, String label) => tester
        .widgetList<StatCard>(find.byType(StatCard))
        .firstWhere((s) => s.label == label);

    testWidgets('band summary copy', (tester) async {
      pool.lens = _healthyLens();
      await pumpLens(tester);
      expect(pool.probes.single, isA<WebLensProbe>());
      expect(find.text('web01'), findsOneWidget);
      expect(find.text('nginx 1.24.0'), findsOneWidget);
      expect(
        find.text('Config OK · 4 vhosts · certs fine'),
        findsOneWidget,
      );
      await dispose(tester);

      pool.lens = _healthyLens(configOk: null);
      await pumpLens(tester);
      expect(
        find.text('Config not tested · 4 vhosts · certs fine'),
        findsOneWidget,
      );
      await dispose(tester);

      // Worst finding wins.
      pool.lens = _lens();
      await pumpLens(tester);
      expect(find.text('Certificate expires in 10 days'), findsOneWidget);
      expect(find.textContaining('Config OK'), findsNothing);
      final band = tester.widget<RiskBand>(
        find
            .ancestor(
              of: find.text('Certificate expires in 10 days'),
              matching: find.byType(RiskBand),
            )
            .first,
      );
      expect(band.status, HealthStatus.warning);
      await dispose(tester);
    });

    testWidgets('three stat cards with values and unknown when section failed',
        (tester) async {
      pool.lens = _lens();
      await pumpLens(tester);
      expect(find.byType(StatCard), findsNWidgets(3));
      expect(card(tester, 'Vhosts').value, '4');
      expect(card(tester, 'Certs').value, '1 expiring');
      // 4 of 1000.
      expect(card(tester, '5xx').value, '0.4%');
      await dispose(tester);

      pool.lens = _healthyLens();
      await pumpLens(tester);
      expect(card(tester, 'Certs').value, 'ok');
      await dispose(tester);

      pool.lens = _lens(
        statusCounts: const {},
        certs: const {},
        vhosts: const [],
        sectionErrors: const {
          WebLensSection.dump: 'Could not read the config dump',
          WebLensSection.certs: 'Could not read certificates',
          WebLensSection.access:
              'Could not read access log: no access with or without sudo -n',
        },
      );
      await pumpLens(tester);
      expect(card(tester, 'Vhosts').value, 'unknown');
      expect(card(tester, 'Certs').value, 'unknown');
      expect(card(tester, '5xx').value, 'unknown');
      // Each failed section says why, in mono.
      for (final reason in [
        'Could not read the config dump',
        'Could not read certificates',
        'Could not read access log: no access with or without sudo -n',
      ]) {
        final t = tester.widget<Text>(find.text(reason));
        expect(t.style?.fontFamily, KelolaType.mono(color: Colors.black).fontFamily);
      }
      await dispose(tester);

      // TLS vhosts but no readable cert: unknown, never "ok".
      pool.lens = _lens(
        certs: const {
          '/etc/ssl/certs/shop.crt': WebCert(path: '/etc/ssl/certs/shop.crt'),
        },
      );
      await pumpLens(tester);
      expect(card(tester, 'Certs').value, 'unknown');
      await dispose(tester);
    });

    testWidgets('pill labels include counts (ALL 4, TLS 3, EXPIRING 1, NO TLS 1)',
        (tester) async {
      pool.lens = _lens();
      await pumpLens(tester);
      for (final label in ['ALL 4', 'TLS 3', 'EXPIRING 1', 'NO TLS 1']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // All is selected first: every vhost row.
      expect(vhostRow('shop.example.com'), findsOneWidget);
      expect(vhostRow('_'), findsOneWidget);

      await tester.tap(find.text('EXPIRING 1'));
      await frames(tester, 4);
      expect(vhostRow('shop.example.com'), findsOneWidget);
      expect(vhostRow('api.example.com'), findsNothing);

      await tester.tap(find.text('NO TLS 1'));
      await frames(tester, 4);
      expect(vhostRow('_'), findsOneWidget);
      expect(vhostRow('shop.example.com'), findsNothing);
      await dispose(tester);
    });

    testWidgets('each pill empty state copy', (tester) async {
      pool.lens = _lens(vhosts: const [], certs: const {});
      await pumpLens(tester);
      expect(find.text('No vhosts found.'), findsOneWidget);
      await dispose(tester);

      pool.lens = _lens(vhosts: const [_plain], certs: const {});
      await pumpLens(tester);
      await tester.tap(find.text('TLS 0'));
      await frames(tester, 4);
      expect(find.text('No TLS vhosts.'), findsOneWidget);
      await tester.tap(find.text('EXPIRING 0'));
      await frames(tester, 4);
      expect(find.text('No vhosts expiring in 21 days.'), findsOneWidget);
      await dispose(tester);

      pool.lens = _lens(vhosts: const [_api]);
      await pumpLens(tester);
      await tester.tap(find.text('NO TLS 0'));
      await frames(tester, 4);
      expect(find.text('No vhosts without TLS.'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('vhost row opens KelolaSheet with mono server strings',
        (tester) async {
      pool.lens = _lens(
        certs: {
          '/etc/ssl/certs/shop.crt': WebCert(
            path: '/etc/ssl/certs/shop.crt',
            notAfter: DateTime.utc(2026, 12, 1, 8, 30),
            sans: const ['shop.example.com', 'www.shop.example.com'],
          ),
          '/etc/ssl/certs/api.crt':
              const WebCert(path: '/etc/ssl/certs/api.crt'),
        },
      );
      await pumpLens(tester);
      await tester.tap(vhostRow('shop.example.com'));
      await frames(tester, 10);
      final sheet = find.byType(KelolaSheet);
      expect(sheet, findsOneWidget);
      final mono = KelolaType.mono(color: Colors.black).fontFamily;
      for (final s in [
        'shop.example.com www.shop.example.com',
        '443 ssl · [::]:443 ssl',
        '/var/www/shop',
        '/etc/ssl/certs/shop.crt',
        '2026-12-01 08:30 UTC',
        'shop.example.com, www.shop.example.com',
        '/etc/nginx/conf.d/shop.conf',
      ]) {
        final f = find.descendant(of: sheet, matching: find.text(s));
        expect(f, findsOneWidget, reason: s);
        expect(tester.widget<Text>(f).style?.fontFamily, mono, reason: s);
      }
      Navigator.of(tester.element(sheet)).pop();
      await frames(tester, 10);

      // Unreadable cert.
      await tester.tap(vhostRow('api.example.com'));
      await frames(tester, 10);
      expect(
        find.descendant(
          of: find.byType(KelolaSheet),
          matching: find.text('certificate unreadable'),
        ),
        findsOneWidget,
      );
      await dispose(tester);
    });

    // Fix 3: a cert inherited from http {} / the server config.
    testWidgets('sheet marks an inherited cert; EXPIRING counts it',
        (tester) async {
      final at = DateTime.now().toUtc();
      const inh = WebVhost(
        serverNames: ['inh.example.com'],
        listen: ['443 ssl'],
        tls: true,
        certPath: '/etc/ssl/certs/http.pem',
        certPaths: ['/etc/ssl/certs/http.pem'],
        inherited: true,
        sourceFile: '/etc/nginx/conf.d/inh.conf',
      );
      pool.lens = _lens(
        readAt: at,
        vhosts: const [_api, inh],
        certs: {
          '/etc/ssl/certs/api.crt': WebCert(
            path: '/etc/ssl/certs/api.crt',
            notAfter: at.add(const Duration(days: 80)),
          ),
          '/etc/ssl/certs/http.pem': WebCert(
            path: '/etc/ssl/certs/http.pem',
            notAfter: at.add(const Duration(days: 5, hours: 2)),
          ),
        },
      );
      await pumpLens(tester);
      expect(find.text('EXPIRING 1'), findsOneWidget);
      await tester.tap(find.text('EXPIRING 1'));
      await frames(tester, 4);
      expect(vhostRow('inh.example.com'), findsOneWidget);
      expect(vhostRow('api.example.com'), findsNothing);

      await tester.tap(vhostRow('inh.example.com'));
      await frames(tester, 10);
      final sheet = find.byType(KelolaSheet);
      final path = find.descendant(
        of: sheet,
        matching: find.text('/etc/ssl/certs/http.pem'),
      );
      expect(path, findsOneWidget);
      expect(
        tester.widget<Text>(path).style?.fontFamily,
        KelolaType.mono(color: Colors.black).fontFamily,
      );
      final note = find.descendant(
        of: sheet,
        matching: find.text('inherited from http {}'),
      );
      expect(note, findsOneWidget);
      final style = tester.widget<Text>(note).style;
      expect(
        style?.fontFamily,
        KelolaType.body(color: Colors.black).fontFamily,
      );
      expect(style?.color, KelolaColors.dark.muted);
      Navigator.of(tester.element(sheet)).pop();
      await frames(tester, 10);

      // An own cert carries no note.
      await tester.tap(find.text('ALL 2'));
      await frames(tester, 4);
      await tester.tap(vhostRow('api.example.com'));
      await frames(tester, 10);
      expect(find.textContaining('inherited from'), findsNothing);
      await dispose(tester);
    });

    test('inherited note names the right config level', () {
      expect(webInheritedCertNote(ServiceId.nginx), 'inherited from http {}');
      expect(
        webInheritedCertNote(ServiceId.apache),
        'inherited from server config',
      );
    });

    // Fix 3: the grant takes cert paths from certsByPath, so an inherited
    // (http-level or global) cert gets its openssl line unchanged.
    test('an inherited cert path reaches the read grant', () {
      final lens = WebLens(
        id: ServiceId.nginx,
        readAt: DateTime.utc(2026, 11, 10),
        vhosts: const [
          WebVhost(
            serverNames: ['inh.example.com'],
            listen: ['443 ssl'],
            tls: true,
            certPath: '/etc/ssl/certs/http.pem',
            certPaths: ['/etc/ssl/certs/http.pem'],
            inherited: true,
          ),
        ],
        certsByPath: const {
          '/etc/ssl/certs/http.pem': WebCert(path: '/etc/ssl/certs/http.pem'),
        },
        toolPaths: const {'openssl': '/usr/bin/openssl', 'tail': '/usr/bin/tail'},
      );
      final g = webReadGrantFor(
        host: host,
        service: _nginx,
        facts: _facts(),
        lens: lens,
      )!;
      expect(
        g.lines,
        contains(
          'hendra ALL=(root) NOPASSWD: /usr/bin/openssl x509 -noout -enddate '
          '-subject -ext subjectAltName -in /etc/ssl/certs/http.pem',
        ),
      );
    });

    testWidgets('error log section renders tail', (tester) async {
      final tail = [
        for (var i = 0; i < 20; i++)
          '2026/11/10 01:31:${(10 + i).toString().padLeft(2, '0')} [error] 3159#3159: line $i',
      ];
      pool.lens = _lens(errorLogTail: tail);
      await pumpLens(tester);
      expect(find.text('ERROR LOG'), findsOneWidget);
      final lines = tester
          .widgetList<JournalLogLine>(find.byType(JournalLogLine))
          .toList();
      expect(lines, isNotEmpty);
      expect(lines.last.message, contains('line 19'));
      expect(lines.last.timestamp, '2026/11/10 01:31:29');
      expect(lines.last.kind, JournalLineKind.error);
      // Not every line inline; the sheet has the full tail.
      expect(lines.length, lessThan(20));
      await tester.tap(find.byType(JournalLogLine).first);
      await frames(tester, 10);
      final sheet = find.byType(KelolaSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.byType(JournalLogLine)),
        findsNWidgets(20),
      );
      Navigator.of(tester.element(sheet)).pop();
      await frames(tester, 10);
      await dispose(tester);

      pool.lens = _lens(
        errorLogTail: const [],
        sectionErrors: const {
          WebLensSection.errorLog:
              'Could not read error log: no access with or without sudo -n',
        },
      );
      await pumpLens(tester);
      expect(find.byType(JournalLogLine), findsNothing);
      expect(
        find.text('Could not read error log: no access with or without sudo -n'),
        findsOneWidget,
      );
      await dispose(tester);
    });

    testWidgets('age label', (tester) async {
      final c = KelolaColors.dark;
      pool.lens = _lens(
        readAt: DateTime.now().toUtc().subtract(const Duration(minutes: 3)),
      );
      await pumpLens(tester);
      final fresh = tester.widget<Text>(find.text('read 3m ago'));
      expect(fresh.style?.color, c.dim);
      await dispose(tester);

      pool.lens = _lens(
        readAt: DateTime.now().toUtc().subtract(const Duration(minutes: 22)),
      );
      await pumpLens(tester);
      final stale = tester.widget<Text>(find.text('read 22m ago'));
      expect(stale.style?.color, c.forHealth(HealthStatus.warning));
      // Data stays visible.
      expect(find.text('ALL 4'), findsOneWidget);
      await dispose(tester);
    });

    testWidgets('sudo hint shown on SudoRequiredException', (tester) async {
      pool.error = SudoRequiredException(
        SudoHintContext.webServices(service: 'nginx'),
      );
      await pumpLens(tester);
      expect(find.byType(ActionableError), findsOneWidget);
      expect(find.textContaining('/etc/sudoers.d/kelola-web'), findsWidgets);
      expect(find.byType(StatCard), findsNothing);
      await dispose(tester);
    });

    testWidgets('real probe output renders through the parser', (tester) async {
      pool.stdout = File(
        'test/fixtures/services/web_lens_nginx_ubuntu.txt',
      ).readAsStringSync();
      await pumpLens(tester);
      expect(card(tester, 'Vhosts').value, '3');
      expect(vhostRow('soon.lab'), findsOneWidget);
      expect(vhostRow('nocert.lab'), findsOneWidget);
      expect(
        find.text('Listens on 443 without a certificate'),
        findsWidgets,
      );
      expect(find.byType(JournalLogLine), findsNWidgets(4));
      await dispose(tester);
    });

    List<StatMeterTone> meterTones(WidgetTester tester) => tester
        .widget<StackedStatMeter>(find.byType(StackedStatMeter))
        .segments
        .map((s) => s.tone)
        .toList();

    testWidgets('5xx segment uses the error tone when the 5xx finding fires',
        (tester) async {
      // 10 of 100 requests: >= 5% with the 100-request minimum.
      pool.lens = _lens(statusCounts: const {200: 85, 404: 5, 502: 10});
      await pumpLens(tester);
      expect(meterTones(tester).last, StatMeterTone.error);
      await dispose(tester);
    });

    testWidgets('5xx segment stays muted below the threshold', (tester) async {
      // 1% of 1000.
      pool.lens = _lens(statusCounts: const {200: 990, 502: 10});
      await pumpLens(tester);
      expect(meterTones(tester).last, StatMeterTone.cached);
      await dispose(tester);

      // 10% but only 99 requests: no finding, still muted.
      pool.lens = _lens(statusCounts: const {200: 89, 502: 10});
      await pumpLens(tester);
      expect(meterTones(tester).last, StatMeterTone.cached);
      await dispose(tester);
    });

    testWidgets('certs unknown when the certs section failed, even if expiring',
        (tester) async {
      pool.lens = _lens(
        sectionErrors: const {
          WebLensSection.certs: 'Could not read 1 of 4 certificates',
        },
      );
      await pumpLens(tester);
      expect(card(tester, 'Certs').value, 'unknown');
      // The expiring cert still shows through its finding.
      expect(find.text('Certificate expires in 10 days'), findsOneWidget);
      await dispose(tester);
    });

    test('ok summary counts vhosts in words: 1 vhost, n vhosts', () {
      final now = DateTime.now().toUtc();
      WebLens l(List<WebVhost> v) =>
          WebLens(id: ServiceId.nginx, readAt: now, configOk: true, vhosts: v);
      expect(webOkSummary(l(const [_plain]), now), 'Config OK · 1 vhost · certs fine');
      expect(
        webOkSummary(l(const [_plain, _plain]), now),
        'Config OK · 2 vhosts · certs fine',
      );
      expect(webOkSummary(l(const []), now), 'Config OK · 0 vhosts · certs fine');
    });

    testWidgets('fact findings render as plain rows, not alarms',
        (tester) async {
      final c = KelolaColors.dark;
      pool.lens = _lens(vhosts: const [_plain], certs: const {});
      await pumpLens(tester);
      // Facts never take the band headline.
      expect(
        find.text('Config OK · 1 vhost · certs fine'),
        findsOneWidget,
      );
      final fact = find.text('Default vhost only');
      expect(fact, findsOneWidget);
      expect(tester.widget<Text>(fact).style?.color, c.muted);
      expect(
        find.ancestor(of: fact, matching: find.byType(RiskBand)),
        findsNothing,
      );
      final band = tester.widget<RiskBand>(find.byType(RiskBand).first);
      expect(band.status, HealthStatus.healthy);
      await dispose(tester);
    });

    testWidgets('age label turns warning only past 15 minutes',
        (tester) async {
      final c = KelolaColors.dark;
      pool.lens = _lens(
        readAt: DateTime.now().toUtc().subtract(const Duration(minutes: 14)),
      );
      await pumpLens(tester);
      expect(tester.widget<Text>(find.text('read 14m ago')).style?.color, c.dim);
      await dispose(tester);

      pool.lens = _lens(
        readAt: DateTime.now().toUtc().subtract(const Duration(minutes: 16)),
      );
      await pumpLens(tester);
      expect(
        tester.widget<Text>(find.text('read 16m ago')).style?.color,
        c.forHealth(HealthStatus.warning),
      );
      await dispose(tester);
    });

    testWidgets('pull-to-refresh re-runs the probe', (tester) async {
      pool.lens = _lens();
      await pumpLens(tester);
      expect(pool.probes, hasLength(1));
      // Same callback the pull gesture fires.
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await frames(tester, 30);
      expect(pool.probes, hasLength(2));
      await dispose(tester);
    });

    Finder reloadRow() => find.widgetWithText(ServiceRow, 'Reload nginx');

    ServiceRow reloadWidget(WidgetTester tester) =>
        tester.widget<ServiceRow>(reloadRow());

    const reloadOk = '@init=systemd\n---TEST---\n'
        '|nginx: the configuration file /etc/nginx/nginx.conf syntax is ok\n'
        '@rc=0\n---RELOAD---\n@rc=0\n---VERIFY---\n|ActiveState=active\n';

    Future<void> tapReloadAndConfirm(WidgetTester tester) async {
      await tester.ensureVisible(reloadRow());
      await tester.tap(reloadRow());
      await frames(tester, 6);
      expect(find.byType(MutateConfirmDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(MutateConfirmDialog),
          matching: find.text('reload'),
        ),
      );
      await frames(tester, 12);
    }

    testWidgets('reload disabled with "Host is read-only." on read-only host',
        (tester) async {
      await repo.setReadOnly(host.id, true);
      pool.lens = _healthyLens();
      await pumpLens(tester);
      final row = reloadWidget(tester);
      expect(row.risk, RiskLevel.mutate);
      expect(row.onTap, isNull);
      expect(row.detail, 'Host is read-only.');
      await tester.ensureVisible(reloadRow());
      await tester.tap(reloadRow());
      await frames(tester, 6);
      expect(find.byType(MutateConfirmDialog), findsNothing);
      expect(pool.probes.whereType<ConfigTestedReloadProbe>(), isEmpty);
      await dispose(tester);
    });

    test('read-only host: the real pool refuses the reload probe', () async {
      await repo.setReadOnly(host.id, true);
      final ro = (await repo.get(host.id))!;
      final real = SshSessionPool(
        repository: repo,
        signer: _BoomSigner(),
        hostKeys: HostKeyPolicy(repo),
        publicBlob: () => Uint8List(0),
      );
      const probe = ConfigTestedReloadProbe(
        id: ServiceId.nginx,
        unit: 'nginx.service',
        testBin: '/usr/sbin/nginx',
      );
      await expectLater(
        real.execute(ro, probe, facts: _facts()),
        throwsA(isA<ReadOnlyViolation>()),
      );
    });

    testWidgets('disabled when configOk == false', (tester) async {
      pool.lens = _healthyLens(configOk: false);
      await pumpLens(tester);
      final row = reloadWidget(tester);
      expect(row.onTap, isNull);
      expect(row.detail, 'Config test failed.');
      await dispose(tester);

      // Not tested yet: enabled; the probe tests again.
      pool.lens = _healthyLens(configOk: null);
      await pumpLens(tester);
      expect(reloadWidget(tester).onTap, isNotNull);
      await dispose(tester);
    });

    testWidgets('reload disabled when the unit or test binary is unknown',
        (tester) async {
      pool.lens = _healthyLens();
      await pumpLens(
        tester,
        service: const DetectedService(
          id: ServiceId.nginx,
          state: ServiceState.running,
          unit: 'nginx.service',
          binaries: {'nginx': '/bin/sh'},
        ),
      );
      expect(reloadWidget(tester).onTap, isNull);
      expect(reloadWidget(tester).detail, 'Service unit unknown.');
      await dispose(tester);

      await pumpLens(
        tester,
        service: const DetectedService(
          id: ServiceId.nginx,
          state: ServiceState.running,
          binaries: {'nginx': '/usr/sbin/nginx'},
        ),
      );
      expect(reloadWidget(tester).detail, 'Service unit unknown.');
      expect(reloadWidget(tester).onTap, isNull);
      await dispose(tester);
    });

    testWidgets('confirm uses confirmUnitAction(verb: reload)', (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = reloadOk;
      await pumpLens(tester);
      await tester.ensureVisible(reloadRow());
      await tester.tap(reloadRow());
      await frames(tester, 6);
      final dialog = find.byType(MutateConfirmDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Reload nginx.service?')),
        findsOneWidget,
      );
      // Cancel: nothing runs.
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Cancel')),
      );
      await frames(tester, 6);
      expect(pool.probes.whereType<ConfigTestedReloadProbe>(), isEmpty);

      await tapReloadAndConfirm(tester);
      final p = pool.probes.whereType<ConfigTestedReloadProbe>().single;
      expect(p.unit, 'nginx.service');
      expect(p.testBin, '/usr/sbin/nginx');
      expect(p.id, ServiceId.nginx);
      await dispose(tester);

      final src = File('lib/presentation/screens/web_lens_screen.dart')
          .readAsStringSync();
      expect(src, contains('confirmUnitAction('));
      expect(src, contains('verb: UnitVerb.reload'));
      expect(src, isNot(contains('DestructiveConfirmSheet')));
    });

    testWidgets('success re-reads lens', (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = reloadOk;
      await pumpLens(tester);
      await tapReloadAndConfirm(tester);
      expect(pool.probes.map((p) => p.runtimeType).toList(), [
        WebLensProbe,
        ConfigTestedReloadProbe,
        WebLensProbe,
      ]);
      await dispose(tester);
    });

    testWidgets('a failed reload shows the host output in mono under the error',
        (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=0\n---RELOAD---\n'
          '|Job for nginx.service failed.\n'
          '|See "systemctl status nginx.service" for details.\n'
          '@rc=1\n---VERIFY---\n|ActiveState=failed\n';
      pool.reloadExit = 1;
      await pumpLens(tester);
      await tapReloadAndConfirm(tester);
      expect(find.text('Reload failed. The reload exited 1.'), findsOneWidget);
      final mono = KelolaType.mono(color: Colors.black).fontFamily;
      for (final line in [
        'Job for nginx.service failed.',
        'See "systemctl status nginx.service" for details.',
      ]) {
        final f = find.text(line);
        expect(f, findsOneWidget, reason: line);
        expect(tester.widget<Text>(f).style?.fontFamily, mono, reason: line);
      }
      await dispose(tester);
    });

    testWidgets('a reload confirmed while a read started meanwhile does not run',
        (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=0\n---RELOAD---\n'
          '@rc=0\n---VERIFY---\n|ActiveState=active\n';
      await pumpLens(tester);
      await tester.ensureVisible(reloadRow());
      await tester.tap(reloadRow());
      await frames(tester, 6);
      expect(find.byType(MutateConfirmDialog), findsOneWidget);
      // A pull-to-refresh starts while the confirm sheet is open.
      pool.lensGate = Completer<void>();
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await frames(tester, 6);
      await tester.tap(
        find.descendant(
          of: find.byType(MutateConfirmDialog),
          matching: find.text('reload'),
        ),
      );
      await frames(tester, 12);
      expect(pool.probes.whereType<ConfigTestedReloadProbe>(), isEmpty);
      pool.lensGate!.complete();
      await frames(tester, 12);
      await dispose(tester);
    });

    testWidgets('testFailed shows mono test output', (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = '@init=systemd\n---TEST---\n'
          '|nginx: [emerg] unknown directive "servr" in /etc/nginx/conf.d/a.conf:3\n'
          '|nginx: configuration file /etc/nginx/nginx.conf test failed\n'
          '@rc=1\n';
      pool.reloadExit = 3;
      await pumpLens(tester);
      await tapReloadAndConfirm(tester);
      expect(find.text('Config test failed. Nothing was reloaded.'), findsOneWidget);
      final mono = KelolaType.mono(color: Colors.black).fontFamily;
      for (final line in [
        'nginx: [emerg] unknown directive "servr" in /etc/nginx/conf.d/a.conf:3',
        'nginx: configuration file /etc/nginx/nginx.conf test failed',
      ]) {
        final f = find.text(line);
        expect(f, findsOneWidget, reason: line);
        expect(tester.widget<Text>(f).style?.fontFamily, mono);
      }
      // Lens not re-read, nothing reloaded.
      expect(pool.probes.whereType<WebLensProbe>(), hasLength(1));
      await dispose(tester);
    });

    testWidgets('reload failure and sudo refusal use the error path',
        (tester) async {
      pool.lens = _healthyLens();
      pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=0\n---RELOAD---\n'
          '|Job for nginx.service failed.\n@rc=1\n---VERIFY---\n|ActiveState=failed\n';
      pool.reloadExit = 1;
      await pumpLens(tester);
      await tapReloadAndConfirm(tester);
      expect(find.textContaining('Reload failed'), findsOneWidget);
      expect(find.textContaining('Job for nginx.service failed.'), findsOneWidget);
      await dispose(tester);

      pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=nosudo\n';
      pool.reloadExit = 4;
      await pumpLens(tester);
      await tapReloadAndConfirm(tester);
      expect(find.byType(ActionableError), findsOneWidget);
      await dispose(tester);
    });

    group('lens sudo grants', () {
      Finder grantButton() => find.widgetWithText(
            ServiceRow,
            'Grant read access for this lens',
          );

      Future<void> tapGrant(WidgetTester tester) async {
        await tester.ensureVisible(grantButton());
        await tester.tap(grantButton());
        await frames(tester, 8);
      }

      Future<void> enterPassword(WidgetTester tester) async {
        await tester.enterText(find.byType(TextField), 's3cret');
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await frames(tester, 20);
      }

      testWidgets('dump sudo hint offers Grant read access with exact lines',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        await pumpLens(tester);
        expect(grantButton(), findsOneWidget);
        expect(tester.widget<ServiceRow>(grantButton()).risk, RiskLevel.mutate);
        // Never Enable Kelola sudo for lens reads: the hint has no button.
        expect(find.text('Enable Kelola sudo…'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ActionableError),
            matching: find.byType(FilledButton),
          ),
          findsNothing,
        );

        await tapGrant(tester);
        expect(find.text('Grant read access for this lens?'), findsOneWidget);
        const first = 'hendra ALL=(root) NOPASSWD: /usr/sbin/nginx -t';
        const second = 'hendra ALL=(root) NOPASSWD: /usr/sbin/nginx -T';
        final shown = find.text('$kelolaWebSudoersPath\n$first\n$second');
        expect(shown, findsOneWidget);
        final mono = KelolaType.mono(color: Colors.black).fontFamily;
        final selectable = tester.widget<SelectableText>(
          find.ancestor(of: shown, matching: find.byType(SelectableText)),
        );
        expect(selectable.style?.fontFamily, mono);
        expect(find.textContaining('second grant'), findsOneWidget);
        expect(find.textContaining('remove stale'), findsOneWidget);
        expect(
          find.text(
            'These rules let this login run the listed commands as root. '
            'The config test loads modules named in the server config, so '
            'Kelola adds it only when that config and its module directories '
            'are root-owned and not writable by others.',
          ),
          findsOneWidget,
        );

        pool.error = null;
        pool.lens = _healthyLens();
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        await enterPassword(tester);

        final probe = pool.probes.whereType<WebSudoersGrantProbe>().single;
        expect(probe.grant.lines, [first, second]);
        expect(pool.stdin, utf8.encode('s3cret\n'));
        // Re-read after the grant.
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(2));
        expect(find.byType(StatCard), findsWidgets);
        await dispose(tester);
      });

      testWidgets('loaded lens with unreadable certs offers one line per safe cert',
          (tester) async {
        final at = DateTime.now().toUtc();
        pool.lens = WebLens(
          id: ServiceId.nginx,
          readAt: at,
          activeState: 'active',
          configOk: true,
          vhosts: const [_shop],
          certsByPath: const {
            '/etc/ssl/certs/shop.crt': WebCert(path: '/etc/ssl/certs/shop.crt'),
            '/etc/ssl/certs/a b.pem': WebCert(path: '/etc/ssl/certs/a b.pem'),
          },
          sectionErrors: const {
            WebLensSection.certs: 'Could not read 2 of 2 certificates',
          },
          toolPaths: const {
            'openssl': '/usr/bin/openssl',
            'tail': '/usr/bin/tail',
          },
          errorLogPath: '/var/log/nginx/error.log',
          accessLogPath: '/var/log/nginx/access.log',
        );
        await pumpLens(tester);
        final row = find.widgetWithText(
          ServiceRow,
          'Grant read access for this lens',
        );
        await tester.ensureVisible(row);
        await tester.tap(row);
        await frames(tester, 8);
        const p = 'hendra ALL=(root) NOPASSWD: ';
        expect(
          find.text([
            kelolaWebSudoersPath,
            '$p/usr/sbin/nginx -t',
            '$p/usr/sbin/nginx -T',
            '$p/usr/bin/openssl x509 -noout -enddate -subject -ext '
                'subjectAltName -in /etc/ssl/certs/shop.crt',
            '$p/usr/bin/tail -n 60 /var/log/nginx/error.log',
            '$p/usr/bin/tail -n 2000 /var/log/nginx/access.log',
          ].join('\n')),
          findsOneWidget,
        );
        expect(find.textContaining('second grant'), findsNothing);
        await dispose(tester);
      });

      testWidgets('no grant offered when the binary is outside system dirs',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        await pumpLens(
          tester,
          service: const DetectedService(
            id: ServiceId.nginx,
            state: ServiceState.running,
            unit: 'nginx.service',
            binaries: {'nginx': '/opt/nginx/sbin/nginx'},
          ),
        );
        expect(find.byType(ActionableError), findsOneWidget);
        expect(grantButton(), findsNothing);
        expect(find.text('Enable Kelola sudo…'), findsNothing);
        expect(find.textContaining('No grant offered'), findsOneWidget);
        await dispose(tester);
      });

      testWidgets(
          'reload SudoRequired on reload leg offers UnitSudoersGrant.tryCreate(verb: reload) on systemd',
          (tester) async {
        pool.lens = _healthyLens();
        pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=0\n'
            '---RELOAD---\n@rc=nosudo\n---VERIFY---\n|ActiveState=active\n';
        pool.reloadExit = 1;
        await pumpLens(tester);
        await tapReloadAndConfirm(tester);
        expect(find.byType(ActionableError), findsOneWidget);
        expect(grantButton(), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Enable Kelola sudo…'));
        await frames(tester, 12);
        final grant = UnitSudoersGrant.tryCreate(
          user: 'hendra',
          verb: 'reload',
          unit: 'nginx.service',
        )!;
        expect(find.text('Allow reload nginx.service?'), findsOneWidget);
        expect(
          find.text('$kelolaUnitSudoersPath\n${grant.line}'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add rule'));
        await frames(tester, 8);
        await enterPassword(tester);
        final probe = pool.probes.whereType<UnitSudoersGrantProbe>().single;
        expect(probe.grant.line, grant.line);
        expect(pool.probes.whereType<WebSudoersGrantProbe>(), isEmpty);
        // The error is gone; Reload can be tried again.
        expect(find.byType(ActionableError), findsNothing);
        expect(reloadWidget(tester).onTap, isNotNull);
        await dispose(tester);
      });

      testWidgets('OpenRC reload failure shows the sudo hint with no grant offer',
          (tester) async {
        await repo.saveFacts(
          host.id,
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
        pool.lens = _healthyLens();
        pool.reloadStdout = '@init=openrc\n---TEST---\n@rc=0\n'
            '---RELOAD---\n@rc=nosudo\n---VERIFY---\n| * status: started\n';
        pool.reloadExit = 1;
        await pumpLens(
          tester,
          service: const DetectedService(
            id: ServiceId.nginx,
            state: ServiceState.running,
            unit: 'nginx',
            binaries: {'nginx': '/usr/sbin/nginx'},
          ),
        );
        await tapReloadAndConfirm(tester);
        final err = find.byType(ActionableError);
        expect(err, findsOneWidget);
        expect(
          find.descendant(of: err, matching: find.byType(FilledButton)),
          findsNothing,
        );
        expect(
          find.descendant(of: err, matching: find.textContaining('rc-service')),
          findsWidgets,
        );
        expect(find.textContaining('Grant read access'), findsNothing);
        await dispose(tester);
      });

      testWidgets('reload test leg sudo refusal offers Grant read access',
          (tester) async {
        pool.lens = _healthyLens();
        pool.reloadStdout = '@init=systemd\n---TEST---\n@rc=nosudo\n';
        pool.reloadExit = 4;
        await pumpLens(tester);
        await tapReloadAndConfirm(tester);
        expect(find.byType(ActionableError), findsOneWidget);
        expect(find.text('Enable Kelola sudo…'), findsNothing);
        await tapGrant(tester);
        expect(
          find.textContaining('hendra ALL=(root) NOPASSWD: /usr/sbin/nginx -t'),
          findsOneWidget,
        );
        await dispose(tester);
      });

      testWidgets('an untrusted binary shows Not granted', (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        pool.grantStdout = '$webGrantUntrustedMarker '
            '${base64Encode(utf8.encode('/usr/sbin/nginx'))}\n';
        await pumpLens(tester);
        await tapGrant(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        await enterPassword(tester);
        expect(
          find.text(
            'Not granted: /usr/sbin/nginx is not root-owned or is writable '
            'by others.',
          ),
          findsOneWidget,
        );
        // Not re-read: nothing was granted.
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(1));
        await dispose(tester);
      });

      testWidgets('skipped log and cert paths are listed as Not granted, the rest installed',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        String b64(String p) => base64Encode(utf8.encode(p));
        pool.grantStdout = '$webGrantSkippedMarker '
            '${b64('/home/deploy/app/log/error.log')}\n'
            '$webGrantOkMarker\n';
        pool.grantExit = 0;
        await pumpLens(tester);
        await tapGrant(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        pool.error = null;
        pool.lens = _healthyLens();
        await enterPassword(tester);
        expect(
          find.text(
            'Read access granted · reading again\n'
            'Not granted: /home/deploy/app/log/error.log is in a directory '
            'that is not root-owned or is writable by others.',
          ),
          findsOneWidget,
        );
        // The rest was installed, so the lens reads again.
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(2));
        await dispose(tester);
      });

      testWidgets('a config refusal names the path in mono, in the result and in ACTIONS',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        const bad = '/etc/nginx/sites-enabled';
        pool.grantStdout = '$webGrantConfigMarker '
            '${base64Encode(utf8.encode(bad))} mode\n'
            '$webGrantOkMarker\n';
        pool.grantExit = 0;
        await pumpLens(tester);
        await tapGrant(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        pool.error = null;
        pool.lens = _healthyLens();
        await enterPassword(tester);
        const copy =
            'Config test not granted: $bad is writable by group or others.';
        expect(
          find.text('Read access granted · reading again\n$copy'),
          findsOneWidget,
        );
        final mono = KelolaType.mono(color: Colors.black).fontFamily;
        bool monoPath(Widget w) {
          if (w is! RichText) return false;
          var found = false;
          w.text.visitChildren((span) {
            if (span is TextSpan &&
                span.text == bad &&
                span.style?.fontFamily == mono) {
              found = true;
            }
            return !found;
          });
          return found;
        }

        expect(find.byWidgetPredicate(monoPath), findsWidgets);
        // The lens read again; the refusal stays in ACTIONS, in mono.
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(2));
        await tester.pump(const Duration(seconds: 10));
        await frames(tester, 8);
        expect(find.text(copy), findsOneWidget);
        expect(find.byWidgetPredicate(monoPath), findsOneWidget);
        await dispose(tester);
      });

      testWidgets('config test lines refused and nothing else: the refusal is the error, no re-read',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        const bad = '/opt/le/options-ssl-nginx.conf';
        pool.grantStdout = '$webGrantConfigMarker '
            '${base64Encode(utf8.encode(bad))} owner\n';
        pool.grantExit = webGrantNothingExit;
        await pumpLens(tester);
        await tapGrant(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        await enterPassword(tester);
        const copy = 'Config test not granted: $bad is not root-owned.';
        expect(find.text(copy), findsWidgets);
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(1));
        // Under the hint's grant row as well, once the snackbar is gone.
        await tester.pump(const Duration(seconds: 10));
        await frames(tester, 8);
        expect(find.text(copy), findsOneWidget);
        await dispose(tester);
      });

      testWidgets('every path skipped: Not granted lines, no re-read',
          (tester) async {
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        pool.grantStdout = '$webGrantSkippedMarker '
            '${base64Encode(utf8.encode('/home/deploy/log/a.log'))}\n';
        pool.grantExit = webGrantNothingExit;
        await pumpLens(tester);
        await tapGrant(tester);
        await tester.tap(find.widgetWithText(FilledButton, 'Add rules'));
        await frames(tester, 8);
        await enterPassword(tester);
        expect(
          find.text(webGrantSkippedCopy('/home/deploy/log/a.log')),
          findsOneWidget,
        );
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(1));
        await dispose(tester);
      });

      testWidgets('certs failing with openssl outside system dirs: no row, one reason',
          (tester) async {
        pool.lens = WebLens(
          id: ServiceId.nginx,
          readAt: DateTime.now().toUtc(),
          activeState: 'active',
          configOk: true,
          vhosts: const [_shop],
          certsByPath: const {
            '/etc/ssl/certs/shop.crt': WebCert(path: '/etc/ssl/certs/shop.crt'),
          },
          sectionErrors: const {
            WebLensSection.certs: 'Could not read 1 of 1 certificates',
          },
          toolPaths: const {
            'openssl': '/opt/ssl/bin/openssl',
            'tail': '/usr/bin/tail',
          },
          errorLogPath: '/var/log/nginx/error.log',
          accessLogPath: '/var/log/nginx/access.log',
        );
        await pumpLens(tester);
        expect(grantButton(), findsNothing);
        expect(
          find.text(
            'Certificate lines not offered: openssl is not in /usr/bin, '
            '/usr/sbin, /bin or /sbin.',
          ),
          findsOneWidget,
        );
        await dispose(tester);
      });

      testWidgets('a lens with nothing a grant can fix shows no grant row',
          (tester) async {
        pool.lens = _healthyLens();
        await pumpLens(tester);
        expect(grantButton(), findsNothing);
        expect(find.textContaining('not offered'), findsNothing);
        await dispose(tester);
      });

      test('no grant without host facts', () async {
        final h = (await repo.get(host.id))!;
        expect(
          webReadGrantFor(host: h, service: _nginx, facts: null),
          isNull,
        );
        expect(
          webReadGrantFor(host: h, service: _nginx, facts: _facts()),
          isNotNull,
        );
      });

      testWidgets('read-only host: the hint says grants are unavailable, never to use one',
          (tester) async {
        await repo.setReadOnly(host.id, true);
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        await pumpLens(tester);
        final err = find.byType(ActionableError);
        expect(err, findsOneWidget);
        final e = tester.widget<ActionableError>(err);
        expect(e.body, contains('read-only'));
        expect(e.body, contains('no grant'));
        expect(e.body, isNot(contains('Grant read access')));
        expect(e.snippet, isNot(contains('Grant read access')));
        expect(find.textContaining('Grant read access'), findsNothing);
        expect(e.onEnableSudo, isNull);
        await dispose(tester);
      });

      testWidgets('read-only host is offered no grant', (tester) async {
        await repo.setReadOnly(host.id, true);
        pool.error = SudoRequiredException(
          SudoHintContext.webServices(service: 'nginx'),
        );
        await pumpLens(tester);
        expect(find.byType(ActionableError), findsOneWidget);
        expect(grantButton(), findsNothing);
        await dispose(tester);
      });
    });

    // Fix 2: Debian / Ubuntu logs are group adm, so joining adm reads them
    // with no sudo at all.
    group('adm group hint', () {
      const errCopy =
          'Could not read error log: no access with or without sudo -n';
      const accCopy =
          'Could not read access log: no access with or without sudo -n';
      const hintCopy =
          'Add your login to the adm group to read web server logs without '
          'sudo:';
      const command = 'sudo usermod -aG adm hendra';

      WebLens admLens({
        String group = 'adm',
        String mode = '640',
        List<String>? loginGroups = const ['hendra', 'sudo'],
        bool bothLogs = false,
      }) =>
          _lens(
            sectionErrors: {
              WebLensSection.errorLog: errCopy,
              WebLensSection.access: accCopy,
            },
            errorLogTail: const [],
            statusCounts: const {},
            errorLogStat: WebLogStat(owner: 'www-data', group: group, mode: mode),
            accessLogStat: bothLogs
                ? WebLogStat(owner: 'root', group: group, mode: mode)
                : null,
            loginGroups: loginGroups,
          );

      testWidgets('shown with the section error, once, in the matching case',
          (tester) async {
        pool.lens = admLens(bothLogs: true);
        await pumpLens(tester);
        expect(find.text(errCopy), findsOneWidget);
        expect(find.text(accCopy), findsOneWidget);
        expect(find.text(hintCopy), findsOneWidget);
        final cmd = find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == command,
        );
        expect(cmd, findsOneWidget);
        expect(
          tester.widget<SelectableText>(cmd).style?.fontFamily,
          KelolaType.mono(color: Colors.white).fontFamily,
        );
        expect(find.text('Takes effect on the next connection.'), findsOneWidget);
        expect(find.text('Reconnect'), findsOneWidget);
        // Kelola never runs usermod itself.
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(1));
        expect(pool.probes, hasLength(1));
        await dispose(tester);
      });

      testWidgets('Alpine-like group nginx: message unchanged, no hint',
          (tester) async {
        pool.lens = admLens(group: 'nginx');
        await pumpLens(tester);
        expect(find.text(errCopy), findsOneWidget);
        expect(find.text(hintCopy), findsNothing);
        expect(find.textContaining('usermod'), findsNothing);
        expect(find.text('Reconnect'), findsNothing);
        await dispose(tester);
      });

      testWidgets('no hint without group read, when already in adm, or groups unknown',
          (tester) async {
        for (final l in [
          admLens(mode: '600'),
          admLens(loginGroups: const ['hendra', 'adm']),
          admLens(loginGroups: null),
        ]) {
          pool.lens = l;
          await pumpLens(tester);
          expect(find.text(errCopy), findsOneWidget);
          expect(find.text(hintCopy), findsNothing);
          expect(find.textContaining('usermod'), findsNothing);
          await dispose(tester);
        }
      });

      testWidgets('copy puts exactly the command on the clipboard',
          (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );
        pool.lens = admLens();
        await pumpLens(tester);
        final copy = find.byTooltip('Copy');
        expect(copy, findsOneWidget);
        await tester.ensureVisible(copy);
        await tester.tap(copy);
        await frames(tester, 4);
        expect(copied, command);
        await dispose(tester);
      });

      testWidgets('Reconnect drops the pooled client once and re-reads the lens',
          (tester) async {
        pool.lens = admLens();
        await pumpLens(tester);
        expect(pool.disconnects, isEmpty);
        final reconnect = find.text('Reconnect');
        await tester.ensureVisible(reconnect);
        await tester.tap(reconnect);
        await frames(tester, 12);
        expect(pool.disconnects, [host.id]);
        expect(pool.probes.whereType<WebLensProbe>(), hasLength(2));
        expect(pool.probes, hasLength(2));
        await dispose(tester);
      });

      testWidgets('read-only host shows the hint too', (tester) async {
        await repo.setReadOnly(host.id, true);
        pool.lens = admLens();
        await pumpLens(tester);
        expect(find.text(hintCopy), findsOneWidget);
        expect(find.text('Reconnect'), findsOneWidget);
        await dispose(tester);
      });
    });
  });

  test('source has no AlertDialog, Card, ListTile', () {
    final src =
        File('lib/presentation/screens/web_lens_screen.dart').readAsStringSync();
    expect(src, isNot(contains('AlertDialog')));
    expect(RegExp(r'\bCard\(').hasMatch(src), isFalse);
    expect(src, isNot(contains('ListTile')));
    expect(src, isNot(contains('FloatingActionButton')));
    expect(RegExp(r'Color\(0x').hasMatch(src), isFalse);
    expect(src, contains('kelolaScrollPadding'));
    expect(src, contains('KelolaSheet'));
  });
}

class _Pool extends SshSessionPool {
  _Pool({required super.repository})
      : super(
          signer: _BoomSigner(),
          hostKeys: HostKeyPolicy(repository),
          publicBlob: () => Uint8List(0),
        );

  final probes = <Probe<dynamic>>[];
  final disconnects = <String>[];
  WebLens? lens;
  String? stdout;
  Object? error;
  String? reloadStdout;
  int reloadExit = 0;
  List<int>? stdin;
  String? grantStdout;
  int grantExit = 5;

  /// When set, lens reads wait for it.
  Completer<void>? lensGate;

  @override
  Future<T> execute<T>(
    Host host,
    Probe<T> probe, {
    HostFacts? facts,
    UnknownHostKeyHandler? onUnknownHostKey,
    void Function(int done, int? total)? onProgress,
    TransferCancel? cancel,
    ProbeScope scope = ProbeScope.host,
    List<int>? stdinBytes,
  }) async {
    probes.add(probe);
    if (probe is WebLensProbe) {
      final gate = lensGate;
      if (gate != null) await gate.future;
      final err = error;
      if (err != null) {
        throw err;
      }
      final out = stdout;
      if (out != null) {
        return probe.parse(out, '', 0);
      }
      return lens! as T;
    }
    if (probe is ConfigTestedReloadProbe) {
      return probe.parse(reloadStdout!, '', reloadExit);
    }
    if (probe is SudoersFileExistsProbe) {
      return false as T;
    }
    if (probe is SudoFlavorProbe) {
      return const SudoRs('0.2.13') as T;
    }
    if (probe is WebSudoersGrantProbe) {
      stdin = stdinBytes;
      final out = grantStdout;
      // The probe's own parse, on the host output the script would print.
      return probe.parse(
        out ?? webGrantOkMarker,
        '',
        out == null ? 0 : grantExit,
      );
    }
    if (probe is UnitSudoersGrantProbe) {
      stdin = stdinBytes;
      return null as T;
    }
    throw StateError('unexpected probe ${probe.runtimeType}');
  }

  @override
  Future<void> disconnect(String hostId) async {
    disconnects.add(hostId);
    await super.disconnect(hostId);
  }
}

class _ReadyEnrollment extends EnrollmentController {
  @override
  EnrollmentState build() {
    return EnrollmentState(publicBlob: Uint8List.fromList(List.filled(64, 1)));
  }
}

class _BoomSigner implements HardwareSigner {
  @override
  Future<HardwareKey> generateKey(String alias) async {
    throw StateError('no key');
  }

  @override
  Future<Uint8List> sign(String alias, Uint8List data) async {
    throw StateError('no key');
  }

  @override
  Future<void> confirmPresence({
    String reason = 'Confirm destructive action',
  }) async {}

  @override
  Future<bool> keyExists(String alias) async => false;

  @override
  Future<void> deleteKey(String alias) async {}
}
