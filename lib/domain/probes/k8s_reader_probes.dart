import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// M52e: creates or renews the read-only `kelola-reader` account and writes
/// [kelolaReaderKubeconfigPath]. The sudo password arrives on stdin only.
/// Never throws for a host that cannot have the account: the result says
/// why, and the host keeps today's reads.
class K8sReaderSetupProbe extends Probe<K8sReaderResult> {
  const K8sReaderSetupProbe();

  @override
  String get auditTitle =>
      'Set up Kubernetes reader $kelolaReaderNamespace/$kelolaReaderName';

  /// The script holds no secret, but it is long; the audit row names what
  /// it does. The token is never in the command, stdout or this row.
  @override
  String auditCommand(HostFacts facts) =>
      'kelola-k8s-reader-setup ${kubectlFlavor(facts).name} '
      '$kelolaReaderNamespace/$kelolaReaderName '
      'duration=$kelolaReaderTokenDuration $kelolaReaderKubeconfigPath';

  @override
  String command(HostFacts facts) =>
      buildK8sReaderSetupScript(kubectlFlavor(facts));

  @override
  K8sReaderResult parse(String stdout, String stderr, int exitCode) =>
      parseK8sReaderOutput(stdout);

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 120);
}

/// M52e: deletes the `kelola-reader` objects (by label only) and the
/// reader kubeconfig. Same password handling as [K8sReaderSetupProbe].
class K8sReaderRemoveProbe extends Probe<K8sReaderResult> {
  const K8sReaderRemoveProbe();

  @override
  String get auditTitle =>
      'Removed Kubernetes reader $kelolaReaderNamespace/$kelolaReaderName';

  @override
  String auditCommand(HostFacts facts) =>
      'kelola-k8s-reader-remove ${kubectlFlavor(facts).name} '
      '$kelolaReaderNamespace/$kelolaReaderName $kelolaReaderKubeconfigPath';

  @override
  String command(HostFacts facts) =>
      buildK8sReaderRemoveScript(kubectlFlavor(facts));

  @override
  K8sReaderResult parse(String stdout, String stderr, int exitCode) =>
      parseK8sReaderOutput(stdout);

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 90);
}

/// M52e: whether [kelolaReaderKubeconfigPath] exists and when its token
/// expires. Reads only the expiry comment, never the token.
class K8sReaderStatusProbe extends Probe<K8sReaderStatus> {
  const K8sReaderStatusProbe();

  @override
  String get auditTitle => 'Checked Kubernetes reader';

  @override
  String command(HostFacts facts) => kelolaReaderSupported(kubectlFlavor(facts))
      ? k8sReaderStatusCommand
      : 'echo $k8sReaderAbsentMarker';

  @override
  K8sReaderStatus parse(String stdout, String stderr, int exitCode) =>
      parseK8sReaderStatus(stdout);

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}
