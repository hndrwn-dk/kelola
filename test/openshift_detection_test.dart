import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/host_facts_parser.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

HostFacts _facts(List<String> runtimes, {String osId = ''}) =>
    HostFacts.undiscovered.copyWith(runtimes: runtimes, osId: osId);

/// A ClusterHealthProbe stdout with the M48 sections.
String _clusterOut({
  String readyz = 'ok',
  String nodes = '{"items":[]}',
  String? openshift,
  String auth = '',
}) {
  return [
    '---HOSTNAME---',
    'crc',
    '---READYZ---',
    readyz,
    '---NODES---',
    nodes,
    if (openshift != null) ...['---OPENSHIFT---', openshift],
    '---AUTH---',
    auth,
  ].join('\n');
}

void main() {
  group('CLI precedence (M48 §1a)', () {
    test('oc wins over k3s and kubectl; k3s still wins over kubectl', () {
      expect(kubectlFlavor(_facts(['oc'])), KubectlFlavor.oc);
      expect(kubectlFlavor(_facts(['kubectl', 'oc'])), KubectlFlavor.oc);
      expect(kubectlFlavor(_facts(['k3s', 'kubectl', 'oc'])), KubectlFlavor.oc);
      expect(kubectlFlavor(_facts(['k3s', 'kubectl'])), KubectlFlavor.k3s);
      expect(kubectlFlavor(_facts(['kubectl'])), KubectlFlavor.kubectl);
      expect(kubectlFlavor(_facts(['docker'])), KubectlFlavor.none);
      expect(kubectlBin(_facts(['oc', 'kubectl'])), 'oc');
    });

    test('hasK8s counts an oc-only bastion', () {
      expect(_facts(['oc']).hasK8s, isTrue);
      expect(_facts(['podman']).hasK8s, isFalse);
    });

    test('HostFactsProbe looks for oc and the CRC off-PATH binary', () {
      const s = HostFactsProbe.script;
      expect(
        s,
        contains('command -v k3s kubectl oc docker podman crictl nerdctl'),
      );
      expect(
        s,
        contains(r'[ -x "$HOME/.crc/bin/oc/oc" ] && echo "$HOME/.crc/bin/oc/oc"'),
      );
    });

    test('the CRC runtime line lands as oc (base name, no stored path)', () {
      final facts = const HostFactsParser().parse([
        '---OS---',
        'ID=rhel',
        'VERSION_ID="9.4"',
        '---RUNTIME---',
        '/home/hendra/.crc/bin/oc/oc',
        '/usr/bin/podman',
        '---NPROC---',
        '4',
      ].join('\n'));
      expect(facts.runtimes, containsAll(['oc', 'podman']));
      expect(facts.runtimes.any((r) => r.contains('/')), isFalse);
      expect(kubectlFlavor(facts), KubectlFlavor.oc);
    });

    test('oc resolves at run time from PATH or ~/.crc/bin/oc/oc', () {
      final f = _facts(['oc']);
      const bin = r'"$(command -v oc || echo "$HOME/.crc/bin/oc/oc")"';
      expect(
        kubectlTry(f, 'get nodes -o json'),
        '$bin get nodes -o json 2>/dev/null || sudo -n $bin get nodes -o json',
      );
      expect(
        kubectlRun(f, 'get pods'),
        '$bin get pods || sudo -n $bin get pods',
      );
      expect(kubectlStdin(f, 'apply -f -', 'a: 1'), contains('then $bin apply -f -'));
      expect(
        kubectlPortForwardCommand(f, resource: 'svc/web', port: 80),
        startsWith('LC_ALL=C $bin '),
      );
    });

    test('vanilla kubectl and k3s lead their sudo argv with a no-op option', () {
      expect(
        kubectlTry(_facts(['kubectl']), 'get nodes'),
        'kubectl get nodes 2>/dev/null || sudo -n kubectl --request-timeout=0 get nodes',
      );
      expect(
        kubectlTry(_facts(['k3s']), 'get nodes'),
        'sudo -n k3s kubectl --request-timeout=0 get nodes 2>/dev/null || k3s kubectl get nodes',
      );
    });
  });

  group('RHCOS node (M48 §1c)', () {
    test('isCoreOsNode for rhcos, scos and fcos only', () {
      for (final id in ['rhcos', 'scos', 'fcos']) {
        expect(_facts(const [], osId: id).isCoreOsNode, isTrue, reason: id);
      }
      for (final id in ['rhel', 'fedora', 'centos', '']) {
        expect(_facts(const [], osId: id).isCoreOsNode, isFalse, reason: id);
      }
    });
  });

  group('cluster kind from the API (M48 §1b)', () {
    test('probe asks config.openshift.io/v1 through kubectlTry', () {
      final cmd = const ClusterHealthProbe().command(_facts(['kubectl']));
      expect(cmd, contains('echo ---OPENSHIFT---'));
      expect(
        cmd,
        contains(
          '{ kubectl get --raw=/apis/config.openshift.io/v1 2>/dev/null || '
          'sudo -n kubectl --request-timeout=0 get --raw=/apis/config.openshift.io/v1 || '
          'echo ---OPENSHIFT_NONE---; }; echo',
        ),
      );
    });

    test('isOpenShift true from the discovery doc', () {
      final h = parseClusterHealth(
        _clusterOut(openshift: _fixture('synthetic_config_openshift_io_v1.json')),
      );
      expect(h.isOpenShift, isTrue);
    });

    test('isOpenShift false on NONE, 404, empty body or other group', () {
      expect(
        parseClusterHealth(_clusterOut(openshift: '---OPENSHIFT_NONE---'))
            .isOpenShift,
        isFalse,
      );
      expect(
        parseClusterHealth(
          _clusterOut(openshift: 'Error from server (NotFound): the server could not find the requested resource (404)'),
        ).isOpenShift,
        isFalse,
      );
      expect(parseClusterHealth(_clusterOut(openshift: '')).isOpenShift, isFalse);
      expect(
        parseClusterHealth(
          _clusterOut(openshift: '{"kind":"APIResourceList","groupVersion":"apps/v1"}'),
        ).isOpenShift,
        isFalse,
      );
    });

    test('isOpenShift null when the section is missing or junk', () {
      expect(parseClusterHealth(_clusterOut()).isOpenShift, isNull);
      expect(
        parseClusterHealth(_clusterOut(openshift: 'garbage \x00 line')).isOpenShift,
        isNull,
      );
      expect(
        parseClusterHealth(_clusterOut(openshift: '{"groupVersion": "config.op'))
            .isOpenShift,
        isNull,
      );
    });

    test('isOpenShift survives withCoreDns', () {
      final h = parseClusterHealth(
        _clusterOut(openshift: _fixture('synthetic_config_openshift_io_v1.json')),
      ).withCoreDns(true);
      expect(h.isOpenShift, isTrue);
      expect(h.coreDnsReady, isTrue);
    });
  });

  group('auth expired (M48 §1d)', () {
    test('probe sets readyz_failed and prints AUTH only on failure', () {
      final cmd = const ClusterHealthProbe().command(_facts(['oc']));
      expect(cmd, contains('readyz_failed=0'));
      expect(
        cmd,
        contains('|| { echo ---READYZ_FAIL---; readyz_failed=1; }; }; echo'),
      );
      expect(cmd, contains('echo ---AUTH---'));
      expect(cmd, contains(r'[ "$readyz_failed" = 1 ] && { {'));
      expect(cmd, contains('} 2>&1 | tail -3; }'));
    });

    for (final line in [
      'error: You must be logged in to the server (Unauthorized)',
      'error: the server has asked for the client to provide credentials',
      'Unauthorized',
    ]) {
      test('"$line" reads as authExpired, never API down', () {
        final h = parseClusterHealth(
          _clusterOut(
            readyz: '---READYZ_FAIL---',
            nodes: '',
            openshift: '---OPENSHIFT_NONE---',
            auth: '$line\nsudo: a password is required',
          ),
        );
        expect(h.authExpired, isTrue);
        expect(h.apiReachable, isTrue);
        expect(h.overall, isNot(HealthStatus.failed));
      });
    }

    test('auth expired + OPENSHIFT_NONE → isOpenShift null (not false)', () {
      final h = parseClusterHealth(
        _clusterOut(
          readyz: '---READYZ_FAIL---',
          nodes: '',
          openshift: '---OPENSHIFT_NONE---',
          auth: 'error: You must be logged in to the server (Unauthorized)',
        ),
      );
      expect(h.authExpired, isTrue);
      expect(h.isOpenShift, isNull);
    });

    test('auth ok + OPENSHIFT_NONE → isOpenShift false', () {
      final h = parseClusterHealth(
        _clusterOut(openshift: '---OPENSHIFT_NONE---'),
      );
      expect(h.authExpired, isFalse);
      expect(h.isOpenShift, isFalse);
    });

    test('any other failure keeps today: API unreachable, failed', () {
      final h = parseClusterHealth(
        _clusterOut(
          readyz: '---READYZ_FAIL---',
          nodes: '',
          auth: 'The connection to the server api.crc.testing:6443 was refused',
        ),
      );
      expect(h.authExpired, isFalse);
      expect(h.apiReachable, isFalse);
      expect(h.overall, HealthStatus.failed);
    });

    test('fleet: expired login is unreadable, not API down', () {
      final read = const FleetClusterProbe().parse(
        _clusterOut(
          readyz: '---READYZ_FAIL---',
          nodes: '',
          openshift: '---OPENSHIFT_NONE---',
          auth: 'error: You must be logged in to the server (Unauthorized)',
        ),
        '',
        0,
      );
      expect(read.health.authExpired, isTrue);
      final summary =
          fleetK8sSummary(read, const WorkloadInventory(rows: []));
      expect(summary.read, isFalse);
      expect(summary.down, isFalse);
    });

    test('fleet: refused in the AUTH text still reads as API down', () {
      final read = const FleetClusterProbe().parse(
        _clusterOut(
          readyz: '---READYZ_FAIL---',
          nodes: '',
          auth: 'Unable to connect to the server: dial tcp 10.0.0.1:6443: connect: connection refused',
        ),
        '',
        0,
      );
      expect(read.connectionRefused, isTrue);
      expect(fleetK8sSummary(read, null), same(FleetK8sSummary.apiDown));
    });
  });

  group('kubeconfig context', () {
    test('probe reads current-context through kubectlTry', () {
      final cmd = const ClusterHealthProbe().command(_facts(['kubectl']));
      expect(cmd, contains('echo ---CONTEXT---'));
      expect(
        cmd,
        contains(
          'kubectl config current-context 2>/dev/null || '
          'sudo -n kubectl --request-timeout=0 config current-context',
        ),
      );
    });

    String withContext(String body) =>
        '${_clusterOut(openshift: '---OPENSHIFT_NONE---')}\n---CONTEXT---\n$body';

    test('context name parsed; errors and junk read as unknown', () {
      expect(
        parseClusterHealth(withContext('default/api-crc-testing:6443/kubeadmin'))
            .kubeContext,
        'default/api-crc-testing:6443/kubeadmin',
      );
      expect(
        parseClusterHealth(withContext('error: current-context is not set'))
            .kubeContext,
        '',
      );
      expect(parseClusterHealth(withContext('')).kubeContext, '');
      expect(parseClusterHealth(_clusterOut()).kubeContext, '');
      expect(
        parseClusterHealth(withContext('lab')).withCoreDns(true).kubeContext,
        'lab',
      );
    });
  });

  group('fleet nodes read', () {
    test('OPENSHIFT JSON after NODES does not count as node JSON', () {
      final read = const FleetClusterProbe().parse(
        _clusterOut(
          nodes: '',
          openshift: _fixture('synthetic_config_openshift_io_v1.json'),
        ),
        '',
        0,
      );
      expect(read.nodesRead, isFalse);
    });

    test('node JSON still counts', () {
      final read = const FleetClusterProbe().parse(
        _clusterOut(
          nodes: _fixture('synthetic_nodes.json'),
          openshift: '---OPENSHIFT_NONE---',
        ),
        '',
        0,
      );
      expect(read.nodesRead, isTrue);
      expect(read.health.nodesTotal, 3);
    });
  });

  group('node MCD state (M48 §2b)', () {
    final h = parseClusterHealth(
      _clusterOut(nodes: _fixture('synthetic_nodes.json')),
    );
    ClusterNodeMembership node(String name) =>
        h.nodes.firstWhere((n) => n.name == name);

    test('Done, Working with update pending, Degraded with reason', () {
      expect(node('master-0').mcdState, McdState.done);
      expect(node('master-0').updatePending, isFalse);
      expect(node('master-0').mcdLabel, 'Ready · Done');
      expect(node('worker-1').mcdState, McdState.working);
      expect(node('worker-1').updatePending, isTrue);
      expect(node('worker-1').mcdLabel, 'Ready · Working (update pending)');
      expect(node('worker-2').mcdState, McdState.degraded);
      expect(
        node('worker-2').mcdLabel,
        'Ready · Degraded: unexpected on-disk state validating against rendered-worker-b2',
      );
      expect(h.mcdDegradedNodes.map((n) => n.name), ['worker-2']);
    });

    test('roles from node-role labels; control plane from master', () {
      expect(node('master-0').roles, ['master', 'control-plane']);
      expect(node('master-0').controlPlane, isTrue);
      expect(node('worker-1').roles, ['worker', 'infra']);
      expect(node('worker-1').nodeRowMeta, startsWith('worker, infra · Ready'));
      expect(h.controlPlaneLabel, '1/1 Ready');
    });

    test('no MCD annotation off OpenShift', () {
      final vanilla = parseClusterHealth(
        _clusterOut(
          nodes:
              '{"items":[{"metadata":{"name":"n1","labels":{}},"status":{"conditions":[{"type":"Ready","status":"True"}]}}]}',
        ),
      );
      expect(vanilla.nodes.single.mcdState, isNull);
      expect(vanilla.nodes.single.mcdLabel, 'Ready');
      expect(vanilla.nodes.single.roles, isEmpty);
    });

    test('junk annotations never throw', () {
      final junk = parseClusterHealth(
        _clusterOut(
          nodes:
              '{"items":[{"metadata":{"name":"n1","annotations":{"machineconfiguration.openshift.io/state":7}}}]}',
        ),
      );
      expect(junk.nodes.single.mcdState, isNull);
    });
  });
}
