import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_parser.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class WorkloadListProbe extends Probe<WorkloadInventory> {
  const WorkloadListProbe();

  @override
  String get auditTitle => 'Listed workloads';

  @override
  String command(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    return 'LC_ALL=C ${kubectlTry(facts, 'get deploy,sts,ds,job,cronjob,pod -A -o json')}';
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
    return 'LC_ALL=C ${kubectlTry(facts, '-n $ns describe $res')}';
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
    return 'LC_ALL=C ${kubectlTry(facts, '-n $ns get events --field-selector $sel -o json')}';
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
    return 'LC_ALL=C ${kubectlTry(facts, '-n $ns top pod$extra --no-headers')}';
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
