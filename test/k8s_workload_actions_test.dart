import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_actions.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/probes/workload_exec_probe.dart';
import 'package:kelola/domain/probes/workload_logs_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

const _web = K8sWorkload(
  kind: K8sKind.deployment,
  namespace: 'prod',
  name: 'web',
  ready: 2,
  desired: 3,
);

const _pod = K8sWorkload(
  kind: K8sKind.pod,
  namespace: 'prod',
  name: 'web-abc',
  ready: 1,
  desired: 1,
  phase: 'Running',
);

void main() {
  final facts = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);

  test('restart and scale are kind-gated; delete and logs are not', () {
    expect(workloadCanRestart(K8sKind.deployment), isTrue);
    expect(workloadCanRestart(K8sKind.pod), isFalse);
    expect(workloadCanScale(K8sKind.statefulSet), isTrue);
    expect(workloadCanScale(K8sKind.daemonSet), isFalse);
    expect(workloadCanDelete(K8sKind.job), isTrue);
    expect(workloadCanLogs(K8sKind.cronJob), isTrue);
    expect(workloadCanExec(K8sKind.pod), isTrue);
    expect(workloadCanExec(K8sKind.deployment), isFalse);
    expect(nextScaleUp(3), 4);
    expect(nextScaleDown(1), 0);
    expect(nextScaleDown(0), 0);
  });

  test('action probe risks and quoted commands never re-detect kubectl', () {
    final restart = WorkloadActionProbe(workload: _web, verb: WorkloadVerb.restart);
    final scale = WorkloadActionProbe(
      workload: _web,
      verb: WorkloadVerb.scale,
      replicas: 4,
    );
    final del = WorkloadActionProbe(workload: _web, verb: WorkloadVerb.delete);

    expect(restart.risk, RiskLevel.mutate);
    expect(scale.risk, RiskLevel.mutate);
    expect(del.risk, RiskLevel.destructive);
    expect(restart.auditTitle, 'Restarted prod/web');
    expect(scale.auditTitle, 'Scaled prod/web');
    expect(del.auditTitle, 'Deleted prod/web');

    expect(
      restart.command(facts),
      contains("-n 'prod' rollout restart 'deployment/web'"),
    );
    expect(scale.command(facts), contains("--replicas=4"));
    expect(del.command(facts), contains("delete 'deployment/web' --wait=false"));
    expect(restart.command(facts), isNot(contains('command -v')));
    expect(restart.command(facts), isNot(contains('2>/dev/null')));
    expect(kubectlRun(facts, 'get ns'), isNot(contains('2>/dev/null')));
  });

  test('logs are read; exec is mutate and quotes the one-shot command', () {
    final logs = WorkloadLogsProbe(_web);
    final exec = WorkloadExecProbe(workload: _pod, line: 'ls /');

    expect(logs.risk, RiskLevel.read);
    expect(exec.risk, RiskLevel.mutate);
    expect(logs.command(facts), contains("logs 'deployment/web'"));
    expect(logs.command(facts), contains('--tail=80'));
    expect(exec.command(facts), contains("exec 'pod/web-abc' -- sh -c 'ls /'"));
    expect(exec.command(facts), isNot(contains(' -it')));
    expect(exec.command(facts), isNot(contains('command -v')));
  });
}
