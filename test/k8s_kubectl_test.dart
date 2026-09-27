import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('flavor follows HostFacts runtimes and never re-detects', () {
    expect(kubectlFlavor(HostFacts.undiscovered), KubectlFlavor.none);
    expect(
      kubectlFlavor(HostFacts.undiscovered.copyWith(runtimes: const ['docker'])),
      KubectlFlavor.none,
    );
    expect(
      kubectlFlavor(HostFacts.undiscovered.copyWith(runtimes: const ['kubectl'])),
      KubectlFlavor.kubectl,
    );
    expect(
      kubectlFlavor(
        HostFacts.undiscovered.copyWith(runtimes: const ['k3s', 'kubectl']),
      ),
      KubectlFlavor.k3s,
    );
  });

  test('list command uses facts binary and -o json, not command -v', () {
    final k3s = WorkloadListProbe().command(
      HostFacts.undiscovered.copyWith(runtimes: const ['k3s']),
    );
    expect(k3s, contains('k3s kubectl'));
    expect(k3s, contains('-o json'));
    expect(k3s, contains('deploy,sts,ds,job,cronjob,pod'));
    expect(k3s, isNot(contains('command -v')));

    final none = WorkloadListProbe().command(HostFacts.undiscovered);
    expect(none, contains('---NO_KUBECTL---'));
    expect(none, isNot(contains('get deploy')));
  });

  test('describe, events, and top are read and quote the object', () {
    final facts = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);
    final describe = WorkloadDescribeProbe(
      kind: K8sKind.deployment,
      namespace: 'prod',
      name: 'web',
    );
    final events = WorkloadEventsProbe(namespace: 'prod', name: 'web');
    final top = WorkloadTopProbe(namespace: 'prod', pod: 'web-abc');

    expect(describe.risk, RiskLevel.read);
    expect(events.risk, RiskLevel.read);
    expect(top.risk, RiskLevel.read);
    expect(const WorkloadListProbe().risk, RiskLevel.read);

    expect(describe.command(facts), contains("-n 'prod' describe 'deployment/web'"));
    expect(describe.command(facts), isNot(contains('command -v')));
    expect(events.command(facts), contains("involvedObject.name=web"));
    expect(events.command(facts), contains('-o json'));
    expect(top.command(facts), contains("top pod 'web-abc'"));
    expect(top.command(facts), contains('--no-headers'));
  });
}
