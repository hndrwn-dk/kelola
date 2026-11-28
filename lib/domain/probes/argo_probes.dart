import 'package:kelola/domain/argocd/argo_app.dart';
import 'package:kelola/domain/argocd/argo_parser.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/k8s_reader.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

const _getApps =
    'get applications.argoproj.io -A -o json --request-timeout=20s';

String _commandFor(HostFacts facts) {
  if (kubectlFlavor(facts) == KubectlFlavor.none) {
    return 'echo ---NO_KUBECTL---';
  }
  final reader = kubectlReaderCli(facts);
  return [
    'export LC_ALL=C',
    // The reader account works but may not list Applications: the screen then
    // says why the read fell back to the login's own identity.
    if (reader != null)
      'if [ -r $kelolaReaderKubeconfig ] && '
          '$reader get --raw=/version >/dev/null 2>&1 && '
          '[ "\$($reader auth can-i list applications.argoproj.io --all-namespaces 2>/dev/null)" = no ]; '
          'then echo ---READER_DENIED---; fi',
    'echo ---APPS---',
    // On failure, re-run once with stderr kept so the section can say why
    // (Forbidden) instead of reading as empty.
    '{ ${kubectlRead(facts, _getApps)} || { echo ---APPS_ERR---; '
        '{ ${kubectlRun(facts, _getApps)}; } 2>&1 >/dev/null | tail -4 | '
        'sed \'s/^/$kOcpErrorPrefix/\'; }; }; echo',
    'true',
  ].join('\n');
}

ArgoApps _parse(String stdout, DateTime Function()? now) => parseArgoApps(
  stdout,
  readAt: now?.call() ?? DateTime.now().toUtc(),
);

/// M49 §2a. The Argo CD `Application` resources in one read through kubectl
/// (never the `argocd` binary or its API). Read-only.
class ArgoAppsProbe extends Probe<ArgoApps> {
  const ArgoAppsProbe({this.now});

  /// Test seam for `ArgoApps.readAt`; defaults to the current UTC time.
  final DateTime Function()? now;

  /// Shared with [FleetArgoProbe] so fleet reads exactly the same.
  static String commandFor(HostFacts facts) => _commandFor(facts);

  @override
  String command(HostFacts facts) => commandFor(facts);

  @override
  ArgoApps parse(String stdout, String stderr, int exitCode) =>
      _parse(stdout, now);

  @override
  String get auditTitle => 'Read Argo CD applications';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}

/// Fleet variant: an unreadable section throws so the row reads "not
/// readable" rather than "no Argo CD". The detail is `ArgoApps.error`, a short
/// reason, never output text.
class FleetArgoProbe extends Probe<ArgoApps> {
  const FleetArgoProbe({this.now});

  final DateTime Function()? now;

  @override
  String get auditTitle => 'Read Argo CD applications (fleet)';

  @override
  String command(HostFacts facts) => ArgoAppsProbe.commandFor(facts);

  @override
  ArgoApps parse(String stdout, String stderr, int exitCode) {
    final apps = _parse(stdout, now);
    final error = apps.error;
    if (error != null) {
      throw K8sReadException('Argo CD applications', error);
    }
    return apps;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 30);
}
