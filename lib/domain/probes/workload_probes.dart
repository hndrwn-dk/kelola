import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/custom_columns.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_parser.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

const _list = 'get deploy,sts,ds,job,cronjob,pod --all-namespaces';

class WorkloadListProbe extends Probe<WorkloadInventory> {
  const WorkloadListProbe();

  @override
  String get auditTitle => 'Listed workloads';

  @override
  String command(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    // M52d: through sudo, names and counts only, never the pod template.
    return 'LC_ALL=C ${kubectlTry(facts, '$_list --output=json', sudoArgs: '$_list ${shellSingleQuote(kWorkloadSudoOutput)}')}';
  }

  @override
  WorkloadInventory parse(String stdout, String stderr, int exitCode) {
    return parseWorkloadList(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

class WorkloadDescribeProbe extends Probe<String> {
  const WorkloadDescribeProbe({
    required this.kind,
    required this.namespace,
    required this.name,
  });

  final K8sKind kind;
  final String namespace;
  final String name;

  @override
  String get auditTitle => 'Described $name';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(namespace);
    final res = shellSingleQuote('${kind.resource}/$name');
    return 'LC_ALL=C ${kubectlTry(facts, '--namespace=$ns describe $res')}';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    return stdout.trim().isEmpty ? stderr.trim() : stdout;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class WorkloadEventsProbe extends Probe<List<K8sEvent>> {
  const WorkloadEventsProbe({
    required this.namespace,
    required this.name,
  });

  final String namespace;
  final String name;

  @override
  String get auditTitle => 'Listed events for $name';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(namespace);
    final sel = shellSingleQuote('involvedObject.name=$name');
    return 'LC_ALL=C ${kubectlTry(facts, '--namespace=$ns get events --field-selector=$sel --output=json')}';
  }

  @override
  List<K8sEvent> parse(String stdout, String stderr, int exitCode) {
    return parseEventList(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class WorkloadTopProbe extends Probe<List<K8sTopRow>> {
  const WorkloadTopProbe({required this.namespace, this.pod});

  final String namespace;
  final String? pod;

  @override
  String get auditTitle => pod == null ? 'Read pod top' : 'Read top for $pod';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(namespace);
    final extra = pod == null ? '' : ' ${shellSingleQuote(pod!)}';
    return 'LC_ALL=C ${kubectlTry(facts, '--namespace=$ns top pod$extra --no-headers')}';
  }

  @override
  List<K8sTopRow> parse(String stdout, String stderr, int exitCode) {
    return parseTopTable(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

/// Waits for a rollout to finish (`kubectl rollout status`). Read-only.
/// Bulk restart runs it between restarts so a namespace is rolled one
/// workload at a time instead of all at once.
class WorkloadRolloutStatusProbe extends Probe<void> {
  const WorkloadRolloutStatusProbe({
    required this.workload,
    this.wait = const Duration(minutes: 2),
  });

  final K8sWorkload workload;
  final Duration wait;

  @override
  String get auditTitle => 'Waited for rollout of ${workload.title}';

  @override
  String command(HostFacts facts) {
    final ns = shellSingleQuote(workload.namespace);
    final res = shellSingleQuote('${workload.kind.resource}/${workload.name}');
    return kubectlOnce(
      facts,
      '-n $ns rollout status $res --timeout=${wait.inSeconds}s',
    );
  }

  @override
  void parse(String stdout, String stderr, int exitCode) {
    if (exitCode != 0) {
      final why = stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
      throw RolloutNotReady(why.split('\n').last);
    }
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => wait + const Duration(seconds: 30);
}

/// A rollout did not become ready in time.
class RolloutNotReady implements Exception {
  RolloutNotReady(this.detail);

  final String detail;

  @override
  String toString() => detail.isEmpty ? 'not ready in time' : detail;
}
