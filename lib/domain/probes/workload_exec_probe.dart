import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class WorkloadExecProbe extends Probe<String> {
  const WorkloadExecProbe({required this.workload, required this.line});

  final K8sWorkload workload;
  final String line;

  @override
  String get auditTitle => 'Exec in ${workload.title}';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(workload.namespace);
    final res = shellSingleQuote('${workload.kind.resource}/${workload.name}');
    final cmd = shellSingleQuote(line);
    return 'LC_ALL=C ${kubectlRun(facts, '-n $ns exec $res -- sh -c $cmd')}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: 'exec', target: workload.title),
      );
    }
    if (exitCode != 0 && stdout.trim().isEmpty) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? stderr.trim() : stdout.trim();
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
