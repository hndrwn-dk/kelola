import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum WorkloadVerb { restart, scale, delete }

class WorkloadActionProbe extends Probe<String> {
  const WorkloadActionProbe({
    required this.workload,
    required this.verb,
    this.replicas,
  });

  final K8sWorkload workload;
  final WorkloadVerb verb;
  final int? replicas;

  @override
  String get auditTitle => switch (verb) {
    WorkloadVerb.restart => 'Restarted ${workload.title}',
    WorkloadVerb.scale => 'Scaled ${workload.title}',
    WorkloadVerb.delete => 'Deleted ${workload.title}',
  };

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(workload.namespace);
    final res = shellSingleQuote('${workload.kind.resource}/${workload.name}');
    final args = switch (verb) {
      WorkloadVerb.restart => '-n $ns rollout restart $res',
      WorkloadVerb.scale =>
        '-n $ns scale $res --replicas=${replicas ?? workload.desired}',
      WorkloadVerb.delete => '-n $ns delete $res --wait=false',
    };
    return 'LC_ALL=C ${kubectlRun(facts, args)}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw KelolaException('No kubectl on this host.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: verb.name, target: workload.title),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? '${verb.name} ok' : stdout.trim();
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk =>
      verb == WorkloadVerb.delete ? RiskLevel.destructive : RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
