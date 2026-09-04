import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Single read round-trip for fleet health grid. Timeout capped at 10s.
class FleetHealthProbe extends Probe<FleetHostHealth> {
  const FleetHealthProbe({this.hostId = '', this.alias = ''});

  final String hostId;
  final String alias;

  @override
  String get auditTitle => 'Fleet health';

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
    final pending = facts.pkg == PackageManager.unknown
        ? r'''
echo "---PENDING---"
echo 0
'''
        : '''
echo "---PENDING---"
{ ${PackageCommands.listUpdates(facts.pkg)} 2>/dev/null || true; } | grep -cve '^\$' || echo 0
''';
    return '''
LC_ALL=C
echo "---UPTIME---"
cat /proc/uptime
echo "---LOAD---"
cat /proc/loadavg
echo "---STAT1---"
head -1 /proc/stat
echo "---STAT2---"
head -1 /proc/stat
echo "---MEM---"
cat /proc/meminfo
echo "---DISK---"
df -PT
$failed
$pending
''';
  }

  @override
  FleetHostHealth parse(String stdout, String stderr, int exitCode) {
    final dash = const DashboardParser().parse(stdout);
    final pending = _pending(stdout);
    return FleetHostHealth(
      hostId: hostId,
      alias: alias,
      reachable: true,
      load1: dash.load1,
      diskRootPercent: dash.diskRootPercent,
      failedUnitCount: dash.failedUnitCount,
      pendingUpdates: pending,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  static int _pending(String stdout) {
    const marker = '---PENDING---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return 0;
    }
    final rest = stdout.substring(i + marker.length).trimLeft();
    final line = rest.split('\n').first.trim();
    return int.tryParse(line) ?? 0;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 10);
}
