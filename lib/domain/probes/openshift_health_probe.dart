import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// M48 §2a. ClusterVersion, ClusterOperators, MachineConfigPools and pending
/// CSRs in one batched read. Runs only when `ClusterHealth.isOpenShift` is
/// true. Read-only: every section is a `get … -o json`.
class OpenShiftHealthProbe extends Probe<OpenShiftHealth> {
  const OpenShiftHealthProbe();

  /// Marker → `get` arguments, in print order.
  static const sections = <(String, String)>[
    ('CLUSTERVERSION', 'get clusterversion version -o json'),
    ('CLUSTEROPERATORS', 'get clusteroperators -o json'),
    ('MCP', 'get machineconfigpools -o json'),
    ('CSR', 'get csr -o json'),
  ];

  /// Shared with `FleetOpenShiftProbe` so fleet reads exactly the same.
  static String commandFor(HostFacts facts) {
    if (kubectlFlavor(facts) == KubectlFlavor.none) {
      return 'echo ---NO_KUBECTL---';
    }
    return [
      'export LC_ALL=C',
      for (final (marker, args) in sections) ...[
        'echo ---$marker---',
        // On failure, re-run once with stderr kept so the section can say
        // why (Forbidden) instead of reading as empty.
        '{ ${kubectlTry(facts, args)} || { { ${kubectlRun(facts, args)}; } 2>&1 >/dev/null | tail -4 | sed \'s/^/$kOcpErrorPrefix/\'; }; }; echo',
      ],
      'true',
    ].join('\n');
  }

  @override
  String command(HostFacts facts) => commandFor(facts);

  @override
  OpenShiftHealth parse(String stdout, String stderr, int exitCode) {
    return parseOpenShiftHealth(stdout);
  }

  @override
  String get auditTitle => 'Read OpenShift health';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
