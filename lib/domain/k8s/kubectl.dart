import 'package:kelola/domain/facts/host_facts.dart';

enum KubectlFlavor { none, kubectl, k3s }

KubectlFlavor kubectlFlavor(HostFacts facts) {
  if (facts.runtimes.contains('k3s')) {
    return KubectlFlavor.k3s;
  }
  if (facts.runtimes.contains('kubectl')) {
    return KubectlFlavor.kubectl;
  }
  return KubectlFlavor.none;
}

String? kubectlBin(HostFacts facts) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.k3s => 'k3s kubectl',
    KubectlFlavor.kubectl => 'kubectl',
    KubectlFlavor.none => null,
  };
}

/// Facts pick the binary. k3s usually needs passwordless sudo; kubectl does not.
String kubectlTry(HostFacts facts, String args) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.none => 'echo ---NO_KUBECTL---',
    KubectlFlavor.k3s =>
      'sudo -n k3s kubectl $args 2>/dev/null || k3s kubectl $args',
    KubectlFlavor.kubectl =>
      'kubectl $args 2>/dev/null || sudo -n kubectl $args',
  };
}
