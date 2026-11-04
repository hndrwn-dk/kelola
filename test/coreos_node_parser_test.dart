import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

String _out({
  String hostname = 'crc',
  String? ostree,
  String units = 'active\nactive',
  String kubelet = '',
  String? crictl,
}) {
  return [
    '---HOSTNAME---',
    hostname,
    '---OSTREE---',
    ostree ?? _fixture('synthetic_rpm_ostree_status.json'),
    '---UNITS---',
    units,
    '---KUBELET---',
    kubelet,
    '---CRICTL---',
    crictl ?? _fixture('synthetic_crictl_ps.json'),
  ].join('\n');
}

void main() {
  test('booted and staged deployments, units, containers', () {
    final s = parseCoreOsNode(_out());
    expect(s.hostname, 'crc');
    expect(s.bootedVersion, '417.94.202410090854-0');
    expect(s.updateStaged, isTrue);
    expect(
      s.updateLabel,
      'update staged (417.94.202411201403-0), reboot pending',
    );
    expect(s.unitState('crio'), 'active');
    expect(s.unitState('kubelet'), 'active');
    expect(s.containersLabel, '3 running');
    expect(s.health, HealthStatus.warning);
  });

  test('kubelet inactive is failed; warnings are kept verbatim', () {
    final s = parseCoreOsNode(
      _out(
        units: 'active\ninactive',
        kubelet: '2026-11-03T10:00:01+0000 crc kubelet[1234]: E1103 failed to sync pod\n-- No entries --',
      ),
    );
    expect(s.unitState('kubelet'), 'inactive');
    expect(s.health, HealthStatus.failed);
    expect(s.kubeletWarnings, [
      '2026-11-03T10:00:01+0000 crc kubelet[1234]: E1103 failed to sync pod',
    ]);
  });

  test('skipped journal and no sudo crictl read as unknown', () {
    final s = parseCoreOsNode(_out(kubelet: 'KELOLA_SKIP', crictl: ''));
    expect(s.kubeletRead, isFalse);
    expect(s.runningContainers, isNull);
    expect(s.containersLabel, 'unknown');
  });

  test('junk never throws', () {
    for (final junk in ['', 'garbage', '---OSTREE---\n{{', '---UNITS---\n\x00']) {
      final s = parseCoreOsNode(junk);
      expect(s.ostreeRead, isFalse);
      expect(s.updateLabel, 'unknown');
      expect(s.health, HealthStatus.unknown);
    }
  });

  test('no staged deployment reads none staged', () {
    final s = parseCoreOsNode(
      _out(ostree: '{"deployments":[{"version":"417.94.1","booted":true}]}'),
    );
    expect(s.updateLabel, 'none staged');
    expect(s.health, HealthStatus.healthy);
  });

  group('bastion link from cached node lists (M48 §4)', () {
    const bastion = FleetK8sSummary(read: true, nodes: ['crc', 'worker-2.lab.local']);
    const other = FleetK8sSummary(read: true, nodes: ['east-1']);

    test('matches short hostname and FQDN either way', () {
      final cache = {'b': bastion, 'o': other, 'n': null};
      expect(clusterBastionFor('crc', cache), 'b');
      expect(clusterBastionFor('CRC', cache), 'b');
      expect(clusterBastionFor('crc.crc.testing', cache), 'b');
      expect(clusterBastionFor('worker-2', cache), 'b');
      expect(clusterBastionFor('nope', cache), isNull);
      expect(clusterBastionFor('', cache), isNull);
    });

    test('never links a host to itself', () {
      expect(clusterBastionFor('crc', {'b': bastion}, selfHostId: 'b'), isNull);
    });

    test('node names survive the fleet cache JSON', () {
      final round = FleetK8sSummary.decode(bastion.encode())!;
      expect(round.nodes, ['crc', 'worker-2.lab.local']);
      expect(FleetK8sSummary.decode('{"read":true}')!.nodes, isEmpty);
    });
  });
}
