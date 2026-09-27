import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/units/shell_quote.dart';

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

/// Write / logs / exec. Same flavor as [kubectlTry], stderr kept.
String kubectlRun(HostFacts facts, String args) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.none => 'echo ---NO_KUBECTL---; exit 1',
    KubectlFlavor.k3s => 'sudo -n k3s kubectl $args || k3s kubectl $args',
    KubectlFlavor.kubectl => 'kubectl $args || sudo -n kubectl $args',
  };
}

/// Host-side port-forward. Binds loopback only; facts pick the binary.
String kubectlPortForwardCommand(
  HostFacts facts, {
  required String resource,
  required int port,
  String namespace = '',
}) {
  final ns = namespace.trim();
  final nsArg = ns.isEmpty ? '' : '-n ${shellSingleQuote(ns)} ';
  final res = shellSingleQuote(resource);
  return 'LC_ALL=C ${kubectlRun(facts, '${nsArg}port-forward --address 127.0.0.1 $res :$port')}';
}

int? parseKubectlForwardPort(String stdout) {
  final match = RegExp(r'Forwarding from 127\.0\.0\.1:(\d+)').firstMatch(stdout);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
