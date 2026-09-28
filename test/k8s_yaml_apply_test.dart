import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_yaml.dart';
import 'package:kelola/domain/probes/workload_yaml_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

const _yaml = '''
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: prod
spec:
  replicas: 3
''';

void main() {
  const workload = K8sWorkload(
    kind: K8sKind.deployment,
    namespace: 'prod',
    name: 'web',
    ready: 2,
    desired: 3,
  );

  test('parseYamlObjectId reads kind name namespace', () {
    final id = parseYamlObjectId(_yaml);
    expect(id.kind, 'Deployment');
    expect(id.name, 'web');
    expect(id.namespace, 'prod');
    expect(() => assertYamlMatchesWorkload(_yaml, workload), returnsNormally);
    expect(
      () => assertYamlMatchesWorkload(
        _yaml.replaceAll('name: web', 'name: other'),
        workload,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('get is read yaml; diff and apply pipe stdin and stay off fleet', () {
    final facts = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);
    final get = WorkloadYamlGetProbe(workload: workload);
    expect(get.risk, RiskLevel.read);
    expect(get.command(facts), contains('-o yaml'));
    expect(get.command(facts), contains("-n 'prod'"));
    expect(get.command(facts), contains('deployment/web'));
    expect(get.command(facts), isNot(contains('command -v')));

    final diff = WorkloadYamlDiffProbe(workload: workload, yaml: _yaml);
    expect(diff.risk, RiskLevel.mutate);
    expect(diff.command(facts), contains('base64 -d'));
    expect(diff.command(facts), contains('diff -f -'));
    expect(diff.parse('a\n', '', 1), contains('a'));

    final apply = WorkloadYamlApplyProbe(workload: workload, yaml: _yaml);
    expect(apply.risk, RiskLevel.destructive);
    expect(apply.auditTitle, contains('prod/web'));
    expect(apply.command(facts), contains('apply -f -'));
    expect(apply.command(facts), contains("-n 'prod'"));
    expect(kubectlStdin(facts, 'apply -f -', _yaml), contains('base64 -d'));
  });
}
