import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class WorkloadLogsProbe extends Probe<String> {
  const WorkloadLogsProbe(this.workload, {this.tail = 80});

  final K8sWorkload workload;
  final int tail;

  @override
  String get auditTitle => 'Read logs for ${workload.title}';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(workload.namespace);
    final res = shellSingleQuote('${workload.kind.resource}/${workload.name}');
    return 'LC_ALL=C ${kubectlRun(facts, '-n $ns logs $res --tail=$tail --timestamps')}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: 'logs', target: workload.title),
      );
    }
    if (exitCode != 0 && stdout.trim().isEmpty) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim();
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
