import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ClusterHealthProbe extends Probe<ClusterHealth> {
  const ClusterHealthProbe();

  static const _argoCrd =
      'get crd applications.argoproj.io -o name --request-timeout=5s';
  static const _argoApps =
      'get applications.argoproj.io -A -o name --request-timeout=5s';

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
      'readyz_failed=0',
      'echo ---READYZ---',
      // --raw prints no trailing newline; the echo keeps the next marker
      // on its own line. A failure sets readyz_failed for ---AUTH---.
      '{ ${kubectlRead(facts, 'get --raw=/readyz')} || { echo ---READYZ_FAIL---; readyz_failed=1; }; }; echo',
      'echo ---NODES---',
      kubectlRead(facts, 'get nodes --output=json'),
      // M48 §1b: cluster kind from the API, independent of the CLI.
      'echo ---OPENSHIFT---',
      '{ ${kubectlRead(facts, 'get --raw=/apis/config.openshift.io/v1')} || echo ---OPENSHIFT_NONE---; }; echo',
      // M49: Argo CD present? The reader cannot read CRDs, so the CRD read
      // uses the login; a Forbidden falls back to listing Applications
      // through the reader. Skipped when readyz failed (section missing).
      'if [ "\$readyz_failed" != 1 ]; then',
      'echo ---ARGO_CRD---',
      'argo_crd=\$( { ${kubectlTry(facts, _argoCrd)} || { echo ---ARGO_CRD_FAIL---; { ${kubectlRun(facts, _argoCrd)}; } 2>&1 >/dev/null | tail -4; }; } 2>/dev/null )',
      r'''printf '%s\n' "$argo_crd"''',
      'case "\$argo_crd" in *orbidden*) echo ---ARGO_NS---; { ${kubectlRead(facts, _argoApps)} && echo ---ARGO_NS_OK---; } 2>&1 | tail -4 ;; esac',
      'fi',
      // M48: kubeconfig context (local, no API call), so a cached
      // OpenShift/Kubernetes label can tell when the cluster changed. The
      // login's own kubeconfig, never the reader's fixed one (M52e).
      'echo ---CONTEXT---',
      kubectlTry(facts, 'config current-context'),
      // M48 §1d: why readyz failed, only when it did (expired oc login).
      'echo ---AUTH---',
      '[ "\$readyz_failed" = 1 ] && { { ${kubectlRun(facts, 'get --raw=/readyz')}; } 2>&1 | tail -3; }',
      'true',
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
