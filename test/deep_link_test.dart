import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/deep_link.dart';

void main() {
  test('parses host, incident, unit, and tunnel', () {
    final host = parseKelolaLink('kelola://host/abc');
    expect(host.hostId, 'abc');
    expect(host.incident, isFalse);
    expect(host.unitName, isNull);
    expect(host.tunnel, isFalse);

    final incident = parseKelolaLink('kelola://host/abc/incident');
    expect(incident.hostId, 'abc');
    expect(incident.incident, isTrue);
    expect(incident.tunnel, isFalse);

    final unit = parseKelolaLink('kelola://host/abc/unit/nginx.service');
    expect(unit.hostId, 'abc');
    expect(unit.unitName, 'nginx.service');
    expect(unit.incident, isFalse);

    final tunnel = parseKelolaLink('kelola://host/abc/tunnel');
    expect(tunnel.hostId, 'abc');
    expect(tunnel.tunnel, isTrue);
    expect(tunnel.incident, isFalse);
  });

  test('unknown suffix and missing unit name open host only', () {
    final nope = parseKelolaLink('kelola://host/abc/nope');
    expect(nope.hostId, 'abc');
    expect(nope.incident, isFalse);
    expect(nope.unitName, isNull);
    expect(nope.tunnel, isFalse);

    final unitOnly = parseKelolaLink('kelola://host/abc/unit');
    expect(unitOnly.hostId, 'abc');
    expect(unitOnly.unitName, isNull);
  });

  test('garbage and host-path fallback', () {
    expect(parseKelolaLink('not-a-link').hostId, isNull);
    expect(parseKelolaLink('').hostId, isNull);
    final fallback = parseKelolaLink('host/abc/unit/sshd.service');
    expect(fallback.hostId, 'abc');
    expect(fallback.unitName, 'sshd.service');
  });
}
