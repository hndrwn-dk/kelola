import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/web_lens.dart';

final now = DateTime.utc(2026, 11, 10, 12);

const _tlsVhost = WebVhost(
  serverNames: ['example.com'],
  listen: ['443 ssl'],
  tls: true,
  certPath: '/etc/ssl/example.pem',
  certPaths: ['/etc/ssl/example.pem'],
  sourceFile: '/etc/nginx/conf.d/example.conf',
);

const _plainVhost = WebVhost(
  serverNames: ['example.com'],
  listen: ['80'],
  sourceFile: '/etc/nginx/conf.d/example.conf',
);

WebLens lens({
  ServiceId id = ServiceId.nginx,
  String? activeState = 'active',
  bool? configOk = true,
  List<WebVhost> vhosts = const [_plainVhost],
  Map<String, WebCert> certs = const {},
  Map<int, int> statusCounts = const {200: 100},
  Map<WebLensSection, String> sectionErrors = const {},
}) {
  return WebLens(
    id: id,
    readAt: now,
    activeState: activeState,
    configOk: configOk,
    vhosts: vhosts,
    certsByPath: certs,
    statusCounts: statusCounts,
    sectionErrors: sectionErrors,
  );
}

WebLens withCertExpiring(Duration inFromNow) => lens(
  vhosts: const [_tlsVhost],
  certs: {
    '/etc/ssl/example.pem': WebCert(
      path: '/etc/ssl/example.pem',
      notAfter: now.add(inFromNow),
      subjectCn: 'example.com',
    ),
  },
);

List<WebFindingLevel> levels(WebLens l) => [
  for (final f in l.findings) f.level,
];

void main() {
  test('healthy lens has no findings', () {
    final l = lens();
    expect(l.findings, isEmpty);
    expect(l.overall, HealthStatus.healthy);
  });

  test('config test failed (rc != 0) → failed', () {
    final l = lens(configOk: false);
    expect(levels(l), [WebFindingLevel.failed]);
    expect(l.findings.single.message, contains('Config test failed'));
    expect(l.overall, HealthStatus.failed);
    // Could not run (no sudo) is not a finding.
    expect(lens(configOk: null).findings, isEmpty);
  });

  test('service not active → failed; unknown state is not a finding', () {
    for (final s in ['inactive', 'failed', 'stopped', 'crashed']) {
      final l = lens(activeState: s);
      expect(levels(l), [WebFindingLevel.failed], reason: s);
      expect(l.overall, HealthStatus.failed);
    }
    for (final s in ['active', 'started', 'reloading']) {
      expect(lens(activeState: s).findings, isEmpty, reason: s);
    }
    expect(lens(activeState: null).findings, isEmpty);
  });

  test('cert expired → failed', () {
    final l = withCertExpiring(const Duration(hours: -1));
    expect(levels(l), [WebFindingLevel.failed]);
    expect(l.findings.single.message, contains('expired'));
    expect(l.findings.single.subject, 'example.com');
    expect(l.overall, HealthStatus.failed);
  });

  test('cert expires in 5 days → failed', () {
    final l = withCertExpiring(const Duration(days: 5, hours: 1));
    expect(levels(l), [WebFindingLevel.failed]);
    expect(l.findings.single.message, contains('5 days'));
  });

  test('cert expires in 7 days → failed', () {
    final l = withCertExpiring(const Duration(days: 7, hours: 1));
    expect(levels(l), [WebFindingLevel.failed]);
  });

  test('cert expires in 8 days → warning', () {
    final l = withCertExpiring(const Duration(days: 8, hours: 1));
    expect(levels(l), [WebFindingLevel.warning]);
    expect(l.overall, HealthStatus.warning);
  });

  test('cert expires in 21 days → warning', () {
    final l = withCertExpiring(const Duration(days: 21, hours: 1));
    expect(levels(l), [WebFindingLevel.warning]);
  });

  test('cert expires in 22 days → nothing', () {
    final l = withCertExpiring(const Duration(days: 22, hours: 1));
    expect(l.findings, isEmpty);
    expect(l.overall, HealthStatus.healthy);
  });

  test('5xx 4.9% of 1000 → nothing', () {
    expect(lens(statusCounts: {200: 951, 500: 49}).findings, isEmpty);
  });

  test('5xx 5% of 100 → warning', () {
    final l = lens(statusCounts: {200: 90, 404: 5, 502: 3, 503: 2});
    expect(levels(l), [WebFindingLevel.warning]);
    expect(l.findings.single.message, contains('5.0%'));
    expect(l.overall, HealthStatus.warning);
  });

  test('5xx 5% with 99 requests → nothing (min 100)', () {
    expect(lens(statusCounts: {200: 94, 500: 5}).findings, isEmpty);
  });

  test('vhost listening on 443 without cert → warning', () {
    for (final listen in [
      '443',
      '443 ssl',
      '[::]:443 ssl http2',
      '0.0.0.0:443',
    ]) {
      final l = lens(
        vhosts: [
          WebVhost(serverNames: const ['nocert.lab'], listen: [listen]),
        ],
      );
      expect(levels(l), [WebFindingLevel.warning], reason: listen);
      expect(l.findings.single.subject, 'nocert.lab');
    }
    // 4430 and 8443 are not 443.
    expect(
      lens(
        vhosts: const [
          WebVhost(serverNames: ['x.lab'], listen: ['4430', '8443 ssl']),
        ],
      ).findings,
      isEmpty,
    );
  });

  test('apache 443 vhost: warning only when no certificate is configured', () {
    const v = WebVhost(
      serverNames: ['example.com'],
      listen: ['*:443'],
      tls: true,
    );
    final none = lens(id: ServiceId.apache, vhosts: const [v]);
    expect(levels(none), [WebFindingLevel.warning]);
    final withCert = lens(
      id: ServiceId.apache,
      vhosts: const [v],
      certs: {
        '/etc/pki/tls/certs/example.crt': WebCert(
          path: '/etc/pki/tls/certs/example.crt',
          notAfter: now.add(const Duration(days: 3, hours: 1)),
        ),
      },
    );
    // -S cannot attribute certs to vhosts; every configured cert is checked.
    expect(levels(withCert), [WebFindingLevel.failed]);
    final unknownCerts = lens(
      id: ServiceId.apache,
      vhosts: const [v],
      sectionErrors: const {
        WebLensSection.certs: 'Could not read certificates',
      },
    );
    expect(unknownCerts.findings, isEmpty);
  });

  test('unreadable cert is a fact, not a finding', () {
    final l = lens(
      vhosts: const [_tlsVhost],
      certs: const {
        '/etc/ssl/example.pem': WebCert(path: '/etc/ssl/example.pem'),
      },
    );
    expect(levels(l), [WebFindingLevel.fact]);
    expect(l.findings.single.message, contains('unreadable'));
    expect(l.overall, HealthStatus.healthy);
    // A referenced cert that was never read (path refused) is unreadable too.
    final missing = lens(vhosts: const [_tlsVhost]);
    expect(levels(missing), [WebFindingLevel.fact]);
  });

  test('default vhost only is a fact', () {
    final l = lens(
      vhosts: const [
        WebVhost(serverNames: ['_'], listen: ['80 default_server']),
      ],
    );
    expect(levels(l), [WebFindingLevel.fact]);
    expect(l.findings.single.message, contains('Default vhost only'));
    expect(l.overall, HealthStatus.healthy);
    final apache = lens(
      id: ServiceId.apache,
      vhosts: const [
        WebVhost(serverNames: ['127.0.0.1'], listen: ['*:80']),
      ],
    );
    expect(levels(apache), [WebFindingLevel.fact]);
  });

  test('worst finding wins; failed before warning before facts', () {
    final l = lens(
      configOk: false,
      vhosts: const [
        WebVhost(serverNames: ['nocert.lab'], listen: ['443']),
        WebVhost(serverNames: ['_'], listen: ['80']),
      ],
    );
    expect(levels(l), [WebFindingLevel.failed, WebFindingLevel.warning]);
    expect(l.overall, HealthStatus.failed);
  });

  test('overall unknown only when nothing could be read', () {
    final nothing = WebLens(
      id: ServiceId.nginx,
      readAt: now,
      sectionErrors: {
        for (final s in WebLensSection.values) s: 'Could not read',
      },
    );
    expect(nothing.overall, HealthStatus.unknown);
    final partial = WebLens(
      id: ServiceId.nginx,
      readAt: now,
      activeState: 'active',
      sectionErrors: {
        for (final s in WebLensSection.values)
          if (s != WebLensSection.active) s: 'Could not read',
      },
    );
    expect(partial.overall, HealthStatus.healthy);
  });
}
