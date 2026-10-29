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
}
