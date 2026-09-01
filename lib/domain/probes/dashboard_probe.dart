import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class DashboardProbe extends Probe<DashboardSnapshot> {
  const DashboardProbe();

  @override
  String command(HostFacts facts) {
    final failed = facts.init == InitSystem.systemd
        ? r'''
echo "---FAILED---"
systemctl list-units --type=service --state=failed --no-legend --plain --no-pager 2>/dev/null | wc -l
echo "---FAILED_NAMES---"
systemctl list-units --type=service --state=failed --no-legend --plain --no-pager 2>/dev/null | awk '{print $1}'
'''
        : r'''
echo "---FAILED---"
echo 0
echo "---FAILED_NAMES---"
''';
    return '''
LC_ALL=C
echo "---UPTIME---"
cat /proc/uptime
echo "---LOAD---"
cat /proc/loadavg
echo "---MEM---"
cat /proc/meminfo
echo "---DISK---"
df -PT
$failed
''';
  }

  @override
  DashboardSnapshot parse(String stdout, String stderr, int exitCode) {
    return const DashboardParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 15);
}
