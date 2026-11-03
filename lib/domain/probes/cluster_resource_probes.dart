import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/cluster_resources_parser.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Shared shape for Wave 2 cluster-wide reads: `kubectl get … -A -o json`.
abstract class _ClusterGetProbe<T> extends Probe<T> {
  const _ClusterGetProbe();

  /// Arguments after `get`, e.g. `svc,endpoints -A -o json`.
  String get getArgs;

  /// Human noun for errors, e.g. `services`.
  String get what;

  T parseJson(String stdout);

  @override
  String command(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    return 'LC_ALL=C ${kubectlTry(facts, 'get $getArgs')}';
  }

  @override
  T parse(String stdout, String stderr, int exitCode) {
    if (!stdout.contains('{')) {
      final detail = stdout.contains('---NO_KUBECTL---')
          ? 'no kubectl on this host'
          : stderr.trim().split('\n').first;
      throw K8sReadException(what, detail);
    }
    return parseJson(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

class ClusterEventsProbe extends _ClusterGetProbe<List<K8sClusterEvent>> {
  const ClusterEventsProbe();

  @override
  String get auditTitle => 'Listed cluster warning events';

  @override
  String get getArgs => 'events -A --field-selector type=Warning -o json';

  @override
  String get what => 'events';

  @override
  List<K8sClusterEvent> parseJson(String stdout) => parseClusterEvents(stdout);
}

class ServiceListProbe extends _ClusterGetProbe<K8sNetworking> {
  const ServiceListProbe();

  @override
  String get auditTitle => 'Listed services and endpoints';

  @override
  String get getArgs => 'svc,endpoints -A -o json';

  @override
  String get what => 'services';

  @override
  K8sNetworking parseJson(String stdout) => parseNetworking(stdout);
}

class StorageListProbe extends _ClusterGetProbe<K8sStorage> {
  const StorageListProbe();

  @override
  String get auditTitle => 'Listed persistent volumes and claims';

  @override
  String get getArgs => 'pv,pvc -A -o json';

  @override
  String get what => 'volumes';

  @override
  K8sStorage parseJson(String stdout) => parseStorage(stdout);
}

class SecurityInventoryProbe extends _ClusterGetProbe<K8sSecurityInventory> {
  const SecurityInventoryProbe();

  @override
  String get auditTitle => 'Listed service accounts, network policies, bindings';

  @override
  String get getArgs => 'sa,networkpolicy,clusterrolebinding -A -o json';

  @override
  String get what => 'security objects';

  @override
  K8sSecurityInventory parseJson(String stdout) =>
      parseSecurityInventory(stdout);
}

/// ConfigMap / Secret **metadata only**. The go-templates print namespace,
/// name, (Secret) type and key names; `.data` values are never emitted, so
/// secret material does not leave the host.
class ConfigInventoryProbe extends Probe<K8sConfigInventory> {
  const ConfigInventoryProbe();

  static const configMapTemplate =
      r'{{range .items}}{{.metadata.namespace}}|{{.metadata.name}}|'
      r'{{range $k, $v := .data}}{{$k}},{{end}}'
      r'{{range $k, $v := .binaryData}}{{$k}},{{end}}{{"\n"}}{{end}}';

  static const secretTemplate =
      r'{{range .items}}{{.metadata.namespace}}|{{.metadata.name}}|{{.type}}|'
      r'{{range $k, $v := .data}}{{$k}},{{end}}{{"\n"}}{{end}}';

  @override
  String get auditTitle => 'Listed ConfigMap and Secret names';

  @override
  String command(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    final cm = shellSingleQuote(configMapTemplate);
    final secret = shellSingleQuote(secretTemplate);
    return [
      'echo ---CM---',
      'LC_ALL=C ${kubectlTry(facts, 'get configmaps -A -o go-template=$cm')} || echo ---CM_FAIL---',
      'echo ---SECRET---',
      'LC_ALL=C ${kubectlTry(facts, 'get secrets -A -o go-template=$secret')} || echo ---SECRET_FAIL---',
    ].join('\n');
  }

  @override
  K8sConfigInventory parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_KUBECTL---')) {
      throw K8sReadException('config', 'no kubectl on this host');
    }
    final inv = parseConfigInventory(stdout);
    if (!inv.configMapsReadable && !inv.secretsReadable) {
      throw K8sReadException('config', stderr.trim().split('\n').first);
    }
    return inv;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

/// Wave 4: kept rollout history. Cluster-wide for home; one namespace for
/// the workload screen (which filters to its owner).
class RolloutHistoryProbe extends _ClusterGetProbe<List<K8sRevision>> {
  const RolloutHistoryProbe({this.namespace});

  final String? namespace;

  @override
  String get auditTitle => namespace == null
      ? 'Listed rollout history'
      : 'Listed rollout history in $namespace';

  @override
  String get getArgs => namespace == null
      ? 'rs,controllerrevision -A -o json'
      : 'rs,controllerrevision -n ${shellSingleQuote(namespace!)} -o json';

  @override
  String get what => 'rollout history';

  @override
  List<K8sRevision> parseJson(String stdout) => parseRolloutHistory(stdout);
}
