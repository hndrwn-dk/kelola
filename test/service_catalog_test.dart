import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';

void main() {
  test('catalog ids are unique', () {
    final ids = kServiceCatalog.map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.toSet(), ServiceId.values.toSet());
  });

  test('every descriptor has a binary and a systemd unit', () {
    for (final d in kServiceCatalog) {
      expect(d.binaries, isNotEmpty, reason: d.id.name);
      expect(d.systemdUnits, isNotEmpty, reason: d.id.name);
      expect(d.openrcServices, isNotEmpty, reason: d.id.name);
    }
  });

  test('descriptorFor(nginx).label == nginx', () {
    expect(descriptorFor(ServiceId.nginx).label, 'nginx');
    for (final id in ServiceId.values) {
      expect(descriptorFor(id).id, id);
    }
  });

  test('catalog rows match the spec table', () {
    final apache = descriptorFor(ServiceId.apache);
    expect(apache.family, ServiceFamily.web);
    expect(apache.systemdUnits, ['httpd.service', 'apache2.service']);
    expect(apache.binaries, ['httpd', 'apache2', 'apachectl', 'apache2ctl']);
    final maria = descriptorFor(ServiceId.mariadb);
    expect(maria.systemdUnits, [
      'mariadb.service',
      'mysqld.service',
      'mysql.service',
    ]);
    expect(descriptorFor(ServiceId.postgres).family, ServiceFamily.database);
  });

  test('matchesSystemdUnit handles exact names and * patterns', () {
    final pg = descriptorFor(ServiceId.postgres);
    expect(pg.matchesSystemdUnit('postgresql.service'), isTrue);
    expect(pg.matchesSystemdUnit('postgresql@15-main.service'), isTrue);
    expect(pg.matchesSystemdUnit('postgresql-15.service'), isTrue);
    expect(pg.matchesSystemdUnit('postgresql@.service'), isTrue);
    expect(pg.matchesSystemdUnit('postgresql.socket'), isFalse);
    expect(pg.matchesSystemdUnit('xpostgresql-15.service'), isFalse);
    expect(pg.matchesSystemdUnit('postgresql-15.service.d'), isFalse);
    final nginx = descriptorFor(ServiceId.nginx);
    expect(nginx.matchesSystemdUnit('nginx.service'), isTrue);
    expect(nginx.matchesSystemdUnit('nginxXservice'), isFalse);
    expect(nginx.matchesSystemdUnit(''), isFalse);
  });

  test('ServiceDetection json round-trips', () {
    final d = ServiceDetection(
      services: const [
        DetectedService(
          id: ServiceId.nginx,
          state: ServiceState.running,
          unit: 'nginx.service',
          version: '1.24.0',
          binaries: {'nginx': '/usr/sbin/nginx'},
        ),
        DetectedService(id: ServiceId.postgres, state: ServiceState.installed),
      ],
      listeningPorts: const [22, 80, 443],
      readAt: DateTime.utc(2026, 11, 10, 8, 30),
    );
    final back = ServiceDetection.fromJson(d.toJson())!;
    expect(back.readAt, d.readAt);
    expect(back.listeningPorts, [22, 80, 443]);
    expect(back.services.length, 2);
    expect(back.services[0].id, ServiceId.nginx);
    expect(back.services[0].state, ServiceState.running);
    expect(back.services[0].unit, 'nginx.service');
    expect(back.services[0].version, '1.24.0');
    expect(back.services[0].binaries, {'nginx': '/usr/sbin/nginx'});
    expect(back.services[1].unit, isNull);
    expect(back.services[1].version, isNull);
    expect(back.services[1].binaries, isEmpty);
  });

  test('fromJson(junk) returns null', () {
    expect(ServiceDetection.fromJson(null), isNull);
    expect(ServiceDetection.fromJson('x'), isNull);
    expect(ServiceDetection.fromJson(42), isNull);
    expect(ServiceDetection.fromJson(<String, dynamic>{}), isNull);
    expect(ServiceDetection.fromJson({'at': 'not a date'}), isNull);
    expect(
      ServiceDetection.fromJson({'at': '2026-11-10T00:00:00Z', 'services': 3}),
      isNull,
    );
  });

  test('fromJson skips junk entries but keeps good ones', () {
    final d = ServiceDetection.fromJson({
      'at': '2026-11-10T00:00:00Z',
      'services': [
        'junk',
        {'id': 'unknown', 'state': 'running'},
        {'id': 'nginx', 'state': 'bogus'},
        {'id': 'apache', 'state': 'failed', 'bin': {'a': 1, 'b': '/x'}},
      ],
      'ports': [80, 'x', 443],
    })!;
    expect(d.services.length, 1);
    expect(d.services.single.id, ServiceId.apache);
    expect(d.services.single.state, ServiceState.failed);
    expect(d.services.single.binaries, {'b': '/x'});
    expect(d.listeningPorts, [80, 443]);
  });

  test('hasLens is true only for web in M52', () {
    expect(hasLens(ServiceId.nginx), isTrue);
    expect(hasLens(ServiceId.apache), isTrue);
    expect(hasLens(ServiceId.mariadb), isFalse);
    expect(hasLens(ServiceId.mysql), isFalse);
    expect(hasLens(ServiceId.postgres), isFalse);
  });
}
