import 'dart:convert';

import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum KubectlFlavor { none, kubectl, k3s, oc }

/// M48 precedence: `oc` → `k3s` → `kubectl`. `oc` is a superset of kubectl
/// and bastions often carry both. k3s stays ahead of kubectl: on k3s hosts a
/// standalone kubectl often has no kubeconfig and falls back to
/// `localhost:8080`.
KubectlFlavor kubectlFlavor(HostFacts facts) {
  if (facts.runtimes.contains('oc')) {
    return KubectlFlavor.oc;
  }
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
    KubectlFlavor.oc => 'oc',
    KubectlFlavor.none => null,
  };
}

/// CRC installs `oc` at `~/.crc/bin/oc/oc` and only puts it on PATH after
/// `eval $(crc oc-env)` in an interactive shell. The binary is resolved at
/// run time (no path is stored in facts). Inline substitution rather than
/// `OC=…;` so the result still composes after `LC_ALL=C` and after a pipe.
const kOcBinary = r'"$(command -v oc || echo "$HOME/.crc/bin/oc/oc")"';

/// Facts pick the binary. k3s usually needs passwordless sudo; kubectl does not.
String kubectlTry(HostFacts facts, String args) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.none => 'echo ---NO_KUBECTL---',
    KubectlFlavor.k3s =>
      'sudo -n k3s kubectl $args 2>/dev/null || k3s kubectl $args',
    KubectlFlavor.kubectl =>
      'kubectl $args 2>/dev/null || sudo -n kubectl $args',
    KubectlFlavor.oc =>
      '$kOcBinary $args 2>/dev/null || sudo -n $kOcBinary $args',
  };
}

/// Reads whose failure says the cluster could not be reached. Same flavor as
/// [kubectlTry], stderr kept. A failure runs [args] again through sudo, so
/// anything that can fail for its own reasons uses [kubectlOnce].
String kubectlRun(HostFacts facts, String args) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.none => 'echo ---NO_KUBECTL---; exit 1',
    KubectlFlavor.k3s => 'sudo -n k3s kubectl $args || k3s kubectl $args',
    KubectlFlavor.kubectl => 'kubectl $args || sudo -n kubectl $args',
    KubectlFlavor.oc => '$kOcBinary $args || sudo -n $kOcBinary $args',
  };
}

/// Picks plain or sudo first, then runs [args] at most once, so a command that
/// fails is neither repeated nor mistaken for a sudo problem, and its exit code
/// survives. `kubectl diff` exits 1 on any difference. If neither can reach the
/// API, [args] never runs, stderr carries both reasons, and the exit code is 2
/// so `kubectl diff` callers do not read it as a difference.
///
/// Sets `LC_ALL=C` itself: a variable prefix cannot precede `if`. The group
/// composes after a pipe, and the check leaves stdin for [args].
String kubectlOnce(HostFacts facts, String args) {
  return switch (kubectlFlavor(facts)) {
    KubectlFlavor.none => '{ echo ---NO_KUBECTL---; exit 1; }',
    KubectlFlavor.k3s =>
      _kubectlOnce('sudo -n k3s kubectl', 'k3s kubectl', args),
    KubectlFlavor.kubectl => _kubectlOnce('kubectl', 'sudo -n kubectl', args),
    KubectlFlavor.oc => _kubectlOnce(kOcBinary, 'sudo -n $kOcBinary', args),
  };
}

String _kubectlOnce(String first, String second, String args) {
  const check = 'get --raw=/version';
  return '{ export LC_ALL=C; '
      'if $first $check >/dev/null 2>&1; then $first $args; '
      'elif $second $check >/dev/null 2>&1; then $second $args; '
      'else $first $check >/dev/null; $second $check >/dev/null; (exit 2); fi; }';
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

/// Pipe YAML on stdin. Base64 avoids a heredoc colliding with the document.
String kubectlStdin(HostFacts facts, String args, String yaml) {
  final b64 = base64Encode(utf8.encode(yaml));
  return 'printf %s ${shellSingleQuote(b64)} | base64 -d | ${kubectlOnce(facts, args)}';
}

int? parseKubectlForwardPort(String stdout) {
  final match = RegExp(r'Forwarding from 127\.0\.0\.1:(\d+)').firstMatch(stdout);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
