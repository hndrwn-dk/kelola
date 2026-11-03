import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';

void main() {
  test('counts by kind and picks up to three worst not-ready rows', () {
    final rows = [
      const K8sWorkload(
        kind: K8sKind.deployment,
        namespace: 'default',
        name: 'web',
        ready: 2,
        desired: 2,
        health: HealthStatus.healthy,
      ),
      const K8sWorkload(
        kind: K8sKind.deployment,
        namespace: 'default',
        name: 'api',
        ready: 1,
        desired: 2,
        health: HealthStatus.warning,
      ),
      const K8sWorkload(
        kind: K8sKind.pod,
        namespace: 'default',
        name: 'api-x',
        ready: 0,
        desired: 1,
        phase: 'CrashLoopBackOff',
        health: HealthStatus.failed,
      ),
      const K8sWorkload(
        kind: K8sKind.daemonSet,
        namespace: 'logging',
        name: 'fluent-bit',
        ready: 0,
        desired: 1,
        health: HealthStatus.failed,
      ),
      const K8sWorkload(
        kind: K8sKind.pod,
        namespace: 'default',
        name: 'pending-a',
        ready: 0,
        desired: 1,
        phase: 'Pending',
        health: HealthStatus.warning,
      ),
      const K8sWorkload(
        kind: K8sKind.statefulSet,
        namespace: 'db',
        name: 'pg',
        ready: 1,
        desired: 1,
        health: HealthStatus.healthy,
      ),
    ];

    final summary = WorkloadHomeSummary.from(rows);
    expect(summary.deployments, 2);
    expect(summary.statefulSets, 1);
    expect(summary.daemonSets, 1);
    expect(summary.pods, 2);
    expect(summary.notReadyCount, 4);
    expect(
      summary.worst.map((w) => w.title).toList(),
      ['default/api-x', 'logging/fluent-bit', 'default/api'],
    );
  });

  test('coreDnsReady is true when a ready kube-system coredns pod exists', () {
    expect(
      coreDnsReadyFromWorkloads(const [
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'kube-system',
          name: 'coredns-abc',
          ready: 1,
          desired: 1,
          phase: 'Running',
          health: HealthStatus.healthy,
        ),
      ]),
      isTrue,
    );
    expect(
      coreDnsReadyFromWorkloads(const [
        K8sWorkload(
          kind: K8sKind.pod,
          namespace: 'kube-system',
          name: 'coredns-abc',
          ready: 0,
          desired: 1,
          phase: 'Pending',
          health: HealthStatus.warning,
        ),
      ]),
      isFalse,
    );
    expect(coreDnsReadyFromWorkloads(const []), isNull);
  });

  test('counts pending, crashloop, and restarting pods separately', () {
    final summary = WorkloadHomeSummary.from(const [
      K8sWorkload(
        kind: K8sKind.pod,
        namespace: 'a',
        name: 'crash',
        ready: 0,
        desired: 1,
        phase: 'Init:CrashLoopBackOff',
        health: HealthStatus.failed,
        restarts: 9,
        podPhase: 'Pending',
      ),
      K8sWorkload(
        kind: K8sKind.pod,
        namespace: 'a',
        name: 'wait',
        ready: 0,
        desired: 1,
        phase: 'Pending · Unschedulable',
        health: HealthStatus.warning,
        podPhase: 'Pending',
      ),
      K8sWorkload(
        kind: K8sKind.pod,
        namespace: 'a',
        name: 'done',
        ready: 0,
        desired: 1,
        phase: 'Succeeded',
        health: HealthStatus.healthy,
        podPhase: 'Succeeded',
      ),
    ]);
    expect(summary.pods, 3);
    expect(summary.notReadyCount, 2);
    expect(summary.pendingCount, 2);
    expect(summary.crashLoopCount, 1);
    expect(summary.restartingCount, 1);
    expect(summary.worst.map((w) => w.name), ['crash', 'wait']);
  });
}
