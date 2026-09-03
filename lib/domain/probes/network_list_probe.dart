import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/network/network_parser.dart';
import 'package:kelola/domain/network/network_snapshot.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class NetworkListProbe extends Probe<NetworkSnapshot> {
  const NetworkListProbe();

  @override
  String get auditTitle => 'Listed network';

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
echo "---ADDR---"
ip -j addr 2>/dev/null || ip addr
echo "---ROUTE---"
ip -j route 2>/dev/null || ip route
echo "---SS---"
ss -tulpn 2>/dev/null || ss -tuln 2>/dev/null || true
''';
  }

  @override
  NetworkSnapshot parse(String stdout, String stderr, int exitCode) {
    return const NetworkParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
