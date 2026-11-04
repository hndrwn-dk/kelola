import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/coreos_node.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// M48 §4: read-only node band for an RHCOS / SCOS / FCOS host.
///
/// Never on this path: the cluster CLI, the node's kubelet credentials
/// directory, or any mutate probe (`coreos_node_probe_test` pins this).
class CoreOsNodeProbe extends Probe<CoreOsNodeStatus> {
  const CoreOsNodeProbe();

  static const _kubeletArgs =
      "-u kubelet -p warning --since '-15min' -n 50 --no-pager -o short-iso";

  @override
  String command(HostFacts facts) {
    final journal = switch (facts.effectiveJournalAccess) {
      JournalAccess.plain => 'journalctl $_kubeletArgs 2>/dev/null',
      JournalAccess.sudo => 'sudo -n journalctl $_kubeletArgs 2>/dev/null',
      JournalAccess.unknown || JournalAccess.denied => 'echo KELOLA_SKIP',
    };
    return [
      'export LC_ALL=C',
      'echo ---HOSTNAME---',
      'hostname -s 2>/dev/null || hostname',
      'echo ---OSTREE---',
      'rpm-ostree status --json 2>/dev/null',
      'echo',
      'echo ---UNITS---',
      'systemctl is-active crio kubelet 2>/dev/null',
      'echo ---KUBELET---',
      journal,
      'echo ---CRICTL---',
      'sudo -n crictl ps -o json 2>/dev/null',
      'true',
    ].join('\n');
  }

  @override
  CoreOsNodeStatus parse(String stdout, String stderr, int exitCode) {
    return parseCoreOsNode(stdout);
  }

  @override
  String get auditTitle => 'Read cluster node status';

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
