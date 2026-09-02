import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/facts/host_facts_parser.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class HostFactsProbe extends Probe<HostFacts> {
  const HostFactsProbe();

  static const script = r'''
LC_ALL=C
echo "---OS---"
cat /etc/os-release
echo "---INIT---"
readlink -f /sbin/init 2>/dev/null
systemctl --version 2>/dev/null | head -1
command -v rc-service openrc-run 2>/dev/null
echo "---PKG---"
command -v apt-get dnf yum zypper apk pacman 2>/dev/null
echo "---FW---"
command -v firewall-cmd ufw nft iptables 2>/dev/null
echo "---JOURNAL---"
id -nG
echo "---ARCH---"
uname -m
echo "---RUNTIME---"
command -v k3s kubectl docker podman crictl nerdctl 2>/dev/null
echo "---NPROC---"
nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0
''';

  @override
  String command(HostFacts facts) => script;

  @override
  HostFacts parse(String stdout, String stderr, int exitCode) {
    return const HostFactsParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  String get auditTitle => 'Discovered host';

  @override
  Duration get timeout => const Duration(seconds: 15);
}
