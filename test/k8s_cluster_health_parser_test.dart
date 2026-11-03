import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';

const _nodesJson = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Node",
      "metadata": {
        "name": "rocky-lab",
        "labels": {
          "node-role.kubernetes.io/control-plane": ""
        }
      },
      "status": {
        "conditions": [
          {"type": "Ready", "status": "True"}
        ],
        "nodeInfo": {
          "kubeletVersion": "v1.31.0",
          "containerRuntimeVersion": "containerd://1.7.22"
        }
      }
    }
  ]
}
''';

void main() {
  test('missing kubectl marker yields missingKubectl', () {
    final health = parseClusterHealth(
      '---NO_KUBECTL---\n',
      hostnameHint: 'rocky-lab',
    );
    expect(health.missingKubectl, isTrue);
    expect(health.overall, HealthStatus.unknown);
  });

  test('readyz ok + matching Ready node is healthy', () {
    final out = '''
---HOSTNAME---
rocky-lab
---READYZ---
ok
---NODES---
$_nodesJson
''';
    final health = parseClusterHealth(out);
    expect(health.missingKubectl, isFalse);
    expect(health.apiReachable, isTrue);
    expect(health.controlPlaneReady, 1);
    expect(health.controlPlaneDesired, 1);
    expect(health.thisHost?.name, 'rocky-lab');
    expect(health.thisHost?.ready, isTrue);
    expect(health.thisHost?.kubeletVersion, 'v1.31.0');
    expect(health.thisHost?.containerRuntime, 'containerd://1.7.22');
    expect(health.thisHostMatched, isTrue);
    expect(health.overall, HealthStatus.healthy);
  });

  test('readyz ok without trailing newline is still reachable', () {
    // Real kubectl: `get --raw=/readyz` prints "ok" with no newline, so the
    // next marker lands on the same line.
    final out = '---HOSTNAME---\nrocky-lab\n---READYZ---\nok---NODES---\n'
        '$_nodesJson';
    final health = parseClusterHealth(out);
    expect(health.apiReachable, isTrue);
    expect(health.controlPlaneReady, 1);
    expect(health.overall, HealthStatus.healthy);
  });

  test('readyz failure marks cluster failed', () {
    final out = '''
---HOSTNAME---
rocky-lab
---READYZ---
---READYZ_FAIL---
---NODES---
$_nodesJson
''';
    final health = parseClusterHealth(out);
    expect(health.apiReachable, isFalse);
    expect(health.overall, HealthStatus.failed);
  });

  test('unmatched hostname leaves thisHost null and overall warning when API ok',
      () {
    final out = '''
---HOSTNAME---
other-box
---READYZ---
ok
---NODES---
$_nodesJson
''';
    final health = parseClusterHealth(out);
    expect(health.thisHost, isNull);
    expect(health.thisHostMatched, isFalse);
    expect(health.overall, HealthStatus.warning);
  });

  test('this host NotReady is warning', () {
    final nodes = _nodesJson.replaceFirst('"status": "True"', '"status": "False"');
    final out = '''
---HOSTNAME---
rocky-lab
---READYZ---
ok
---NODES---
$nodes
''';
    final health = parseClusterHealth(out);
    expect(health.thisHost?.ready, isFalse);
    expect(health.overall, HealthStatus.warning);
  });

  test('counts every node, names NotReady ones, and surfaces pressure', () {
    const out = r'''
---HOSTNAME---
cp-1
---READYZ---
ok
---NODES---
{
  "kind": "List",
  "items": [
    {
      "kind": "Node",
      "metadata": {"name": "cp-1", "labels": {"node-role.kubernetes.io/control-plane": ""}},
      "status": {
        "conditions": [
          {"type": "MemoryPressure", "status": "False"},
          {"type": "DiskPressure", "status": "False"},
          {"type": "Ready", "status": "True"}
        ],
        "nodeInfo": {"kubeletVersion": "v1.31.0", "containerRuntimeVersion": "containerd://1.7.22"}
      }
    },
    {
      "kind": "Node",
      "metadata": {"name": "worker-1", "labels": {}},
      "status": {
        "conditions": [
          {"type": "DiskPressure", "status": "True"},
          {"type": "Ready", "status": "True"}
        ],
        "nodeInfo": {"kubeletVersion": "v1.31.0", "containerRuntimeVersion": "containerd://1.7.22"}
      }
    },
    {
      "kind": "Node",
      "metadata": {"name": "worker-2", "labels": {}},
      "status": {
        "conditions": [{"type": "Ready", "status": "Unknown"}],
        "nodeInfo": {"kubeletVersion": "v1.30.4", "containerRuntimeVersion": "cri-o://1.30.1"}
      }
    }
  ]
}
''';
    final health = parseClusterHealth(out);
    expect(health.nodesTotal, 3);
    expect(health.nodesReady, 2);
    expect(health.nodesLabel, '2/3 Ready');
    expect(health.notReadyNodes, ['worker-2']);
    expect(health.pressuredNodes, ['worker-1: DiskPressure']);
    expect(health.controlPlaneLabel, '1/1 Ready');
    expect(health.thisHost?.membershipLabel,
        'Ready · kubelet v1.31.0 · containerd 1.7.22');
    expect(health.overall, HealthStatus.warning);
  });

  test('withCoreDns keeps the node list', () {
    const out = '''
---HOSTNAME---
rocky-lab
---READYZ---
ok
---NODES---
$_nodesJson
''';
    final health = parseClusterHealth(out).withCoreDns(true);
    expect(health.nodesLabel, '1/1 Ready');
    expect(health.coreDnsReady, isTrue);
    expect(health.overall, HealthStatus.healthy);
  });

  test('runtimeLabel splits scheme and version', () {
    expect(runtimeLabel('containerd://1.7.22'), 'containerd 1.7.22');
    expect(runtimeLabel('docker'), 'docker');
  });
}
