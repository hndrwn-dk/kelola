import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_parser.dart';
import 'package:kelola/domain/k8s/workload_view.dart';

const _listJson = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Deployment",
      "metadata": {"name": "web", "namespace": "prod"},
      "spec": {"replicas": 3},
      "status": {"replicas": 3, "readyReplicas": 2, "availableReplicas": 2}
    },
    {
      "kind": "Pod",
      "metadata": {"name": "web-abc", "namespace": "prod"},
      "status": {
        "phase": "Running",
        "containerStatuses": [
          {"ready": true, "restartCount": 1},
          {"ready": true, "restartCount": 0}
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "job-xyz", "namespace": "kube-system"},
      "status": {"phase": "Failed", "containerStatuses": [{"ready": false}]}
    },
    {
      "kind": "Job",
      "metadata": {"name": "migrate", "namespace": "prod"},
      "spec": {"completions": 1},
      "status": {"succeeded": 1}
    }
  ]
}
''';

void main() {
  test('parses get -o json ready rollups and ignores unknown kinds', () {
    final inv = parseWorkloadList(_listJson);
    expect(inv.missingKubectl, isFalse);
    expect(inv.rows, hasLength(4));
    final web = inv.rows.firstWhere((w) => w.name == 'web');
    expect(web.kind, K8sKind.deployment);
    expect(web.namespace, 'prod');
    expect(web.ready, 2);
    expect(web.desired, 3);
    expect(web.health, HealthStatus.warning);
    expect(web.readyLabel, '2/3');

    final pod = inv.rows.firstWhere((w) => w.name == 'web-abc');
    expect(pod.ready, 2);
    expect(pod.desired, 2);
    expect(pod.phase, 'Running');
    expect(pod.health, HealthStatus.healthy);

    final failed = inv.rows.firstWhere((w) => w.name == 'job-xyz');
    expect(failed.health, HealthStatus.failed);
  });

  test('namespace and kind filters are client-side', () {
    final rows = parseWorkloadList(_listJson).rows;
    expect(
      WorkloadListView.build(rows, namespace: 'prod').rows.map((w) => w.name),
      ['web', 'web-abc', 'migrate'],
    );
    expect(
      WorkloadListView.build(rows, kind: K8sKind.pod).rows.map((w) => w.name),
      ['web-abc', 'job-xyz'],
    );
    expect(
      WorkloadListView.build(rows, notReadyOnly: true).rows.map((w) => w.name),
      ['web', 'job-xyz'],
    );
  });

  test('sentinel and junk JSON are empty, not a crash', () {
    expect(parseWorkloadList('---NO_KUBECTL---').missingKubectl, isTrue);
    expect(parseWorkloadList('not-json').rows, isEmpty);
  });

  test('parses events JSON and top table', () {
    final events = parseEventList(r'''
{
  "items": [
    {
      "type": "Warning",
      "reason": "Unhealthy",
      "message": "Readiness probe failed",
      "lastTimestamp": "2026-09-27T01:00:00Z"
    }
  ]
}
''');
    expect(events, hasLength(1));
    expect(events.single.reason, 'Unhealthy');
    expect(events.single.message, 'Readiness probe failed');

    final top = parseTopTable(
      'NAME       CPU    MEMORY\n'
      'web-abc    12m    64Mi\n'
      'web-def    3m     32Mi\n',
    );
    expect(top.map((r) => r.name), ['web-abc', 'web-def']);
    expect(top.first.cpu, '12m');
    expect(top.first.memory, '64Mi');
  });
}
