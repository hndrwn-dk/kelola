import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_yaml.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class WorkloadYamlGetProbe extends Probe<String> {
  const WorkloadYamlGetProbe({required this.workload});

  final K8sWorkload workload;

  @override
  String get auditTitle => 'Read YAML for ${workload.title}';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(workload.namespace);
    final res = shellSingleQuote('${workload.kind.resource}/${workload.name}');
    return 'LC_ALL=C ${kubectlTry(facts, '-n $ns get $res -o yaml')}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    final body = stdout.trim().isEmpty ? stderr.trim() : stdout;
    if (exitCode != 0 && body.isEmpty) {
      throw KelolaException('exit $exitCode');
    }
    return body;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class WorkloadYamlDiffProbe extends Probe<String> {
  const WorkloadYamlDiffProbe({required this.workload, required this.yaml});

  final K8sWorkload workload;
  final String yaml;

  @override
  String get auditTitle => 'Diffed ${workload.title}';

  @override
  String command(HostFacts facts) {
    assertYamlMatchesWorkload(yaml, workload);
    final ns = shellSingleQuote(workload.namespace);
    return 'LC_ALL=C ${kubectlStdin(facts, '-n $ns diff -f -', yaml)}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: 'diff', target: workload.title),
      );
    }
    if (exitCode > 1) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    final body = stdout.trim().isEmpty ? stderr.trim() : stdout.trim();
    return body.isEmpty ? 'no diff' : body;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

class WorkloadYamlApplyProbe extends Probe<String> {
  const WorkloadYamlApplyProbe({required this.workload, required this.yaml});

  final K8sWorkload workload;
  final String yaml;

  @override
  String get auditTitle => 'Applied ${workload.title}';

  @override
  String command(HostFacts facts) {
    assertYamlMatchesWorkload(yaml, workload);
    final ns = shellSingleQuote(workload.namespace);
    return 'LC_ALL=C ${kubectlStdin(facts, '-n $ns apply -f -', yaml)}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: 'apply', target: workload.title),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? 'applied ${workload.title}' : stdout.trim();
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 45);
}
