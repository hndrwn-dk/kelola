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
}
