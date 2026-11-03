import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ClusterHealthProbe extends Probe<ClusterHealth> {
  const ClusterHealthProbe();

  @override
  String get auditTitle => 'Read cluster health';

  @override
  String command(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    return [
      'echo ---HOSTNAME---',
      'hostname -s 2>/dev/null || hostname',
      'echo ---READYZ---',
      // --raw prints no trailing newline; the echo keeps the next marker
      // on its own line.
      '{ ${kubectlTry(facts, 'get --raw=/readyz')} || echo ---READYZ_FAIL---; }; echo',
      'echo ---NODES---',
      kubectlTry(facts, 'get nodes -o json'),
    ].join('\n');
  }

  @override
  ClusterHealth parse(String stdout, String stderr, int exitCode) {
    return parseClusterHealth(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
