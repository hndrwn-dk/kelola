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

  test('pod waiting reason CrashLoopBackOff becomes phase and failed health',
      () {
    final inv = parseWorkloadList(r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Pod",
      "metadata": {"name": "api-x", "namespace": "default"},
      "status": {
        "phase": "Running",
        "containerStatuses": [
          {
            "ready": false,
            "restartCount": 14,
            "state": {"waiting": {"reason": "CrashLoopBackOff"}}
          }
        ]
      }
    }
  ]
}
''');
    final pod = inv.rows.single;
    expect(pod.phase, 'CrashLoopBackOff');
    expect(pod.health, HealthStatus.failed);
    expect(pod.ready, 0);
    expect(pod.desired, 1);
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

  test('wave 1: restarts, init errors, config errors, completed, scaled to 0',
      () {
    const json = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Pod",
      "metadata": {"name": "flappy", "namespace": "prod"},
      "status": {
        "phase": "Running",
        "containerStatuses": [
          {"ready": true, "restartCount": 7,
           "lastState": {"terminated": {"reason": "OOMKilled"}}}
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "init-bad", "namespace": "prod"},
      "status": {
        "phase": "Pending",
        "initContainerStatuses": [
          {"ready": false, "restartCount": 3,
           "state": {"waiting": {"reason": "CrashLoopBackOff"}}}
        ],
        "containerStatuses": [
          {"ready": false, "restartCount": 0,
           "state": {"waiting": {"reason": "PodInitializing"}}}
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "no-secret", "namespace": "prod"},
      "status": {
        "phase": "Pending",
        "containerStatuses": [
          {"ready": false, "state": {"waiting": {"reason": "CreateContainerConfigError"}}}
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "unsched", "namespace": "prod"},
      "status": {
        "phase": "Pending",
        "conditions": [
          {"type": "PodScheduled", "status": "False", "reason": "Unschedulable"}
        ]
      }
    },
    {
      "kind": "Pod",
      "metadata": {"name": "report-done", "namespace": "batch"},
      "status": {
        "phase": "Succeeded",
        "containerStatuses": [{"ready": false, "restartCount": 0}]
      }
    },
    {
      "kind": "Deployment",
      "metadata": {"name": "parked", "namespace": "prod"},
      "spec": {"replicas": 0},
      "status": {}
    },
    {
      "kind": "Deployment",
      "metadata": {"name": "surging", "namespace": "prod"},
      "spec": {"replicas": 3},
      "status": {"replicas": 4, "readyReplicas": 3}
    }
  ]
}
''';
    final rows = {for (final r in parseWorkloadList(json).rows) r.name: r};

    final flappy = rows['flappy']!;
    expect(flappy.restarts, 7);
    expect(flappy.health, HealthStatus.warning);
    expect(flappy.restarting, isTrue);
    expect(flappy.phase, 'Running · last OOMKilled');
    expect(workloadMeta(flappy), 'pod · 1/1 · Running · last OOMKilled · 7 restarts');

    final initBad = rows['init-bad']!;
    expect(initBad.phase, 'Init:CrashLoopBackOff');
    expect(initBad.health, HealthStatus.failed);
    expect(initBad.crashLooping, isTrue);
    expect(initBad.pending, isTrue);
    expect(initBad.restarts, 3);

    expect(rows['no-secret']!.health, HealthStatus.failed);
    expect(rows['no-secret']!.phase, 'CreateContainerConfigError');

    expect(rows['unsched']!.phase, 'Pending · Unschedulable');
    expect(rows['unsched']!.health, HealthStatus.warning);

    final done = rows['report-done']!;
    expect(done.health, HealthStatus.healthy);
    expect(done.notReady, isFalse);

    final parked = rows['parked']!;
    expect(parked.health, HealthStatus.healthy);
    expect(parked.phase, 'scaled to 0');
    expect(parked.notReady, isFalse);

    final surging = rows['surging']!;
    expect(surging.desired, 3);
    expect(surging.health, HealthStatus.healthy);
  });

  test('last termination reason Unknown reads as an unknown exit', () {
    const json = '''
{"items": [{
  "kind": "Pod",
  "metadata": {"name": "nginx-7b8b87776c-tksjt", "namespace": "default"},
  "status": {
    "phase": "Running",
    "containerStatuses": [{
      "ready": true,
      "restartCount": 5,
      "lastState": {"terminated": {"reason": "Unknown", "exitCode": 255}}
    }]
  }
}]}
''';
    final pod = parseWorkloadList(json).rows.single;
    expect(pod.phase, 'Running · last exit unknown');
    expect(
      workloadMeta(pod),
      'pod · 1/1 · Running · last exit unknown · 5 restarts',
    );
  });
}
