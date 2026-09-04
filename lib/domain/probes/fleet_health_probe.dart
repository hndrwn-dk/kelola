import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Single batched read for fleet tiles. No sleep / dual /proc/stat.
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
echo "---SECURITY---"
echo 0
'''
        : '''
echo "---PENDING---"
{ ${PackageCommands.listUpdates(facts.pkg)} 2>/dev/null || true; } | grep -cve '^\$' || echo 0
echo "---SECURITY---"
{ ${PackageCommands.listSecurity(facts.pkg)} 2>/dev/null || true; } | grep -cve '^\$\\|^N/A' || echo 0
''';
    final nproc = facts.nprocCores != null
        ? 'echo "---NPROC---"\necho ${facts.nprocCores}\n'
        : r'''
echo "---NPROC---"
nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0
''';
    return '''
LC_ALL=C
echo "---UPTIME---"
cat /proc/uptime
echo "---LOAD---"
cat /proc/loadavg
$nproc
echo "---MEM---"
cat /proc/meminfo
echo "---DISK---"
df -PT
$failed
$pending
echo "---CONTAINERS---"
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null \\
    || sudo -n docker ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null \\
    || true
elif command -v podman >/dev/null 2>&1; then
  podman ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null \\
    || sudo -n podman ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null \\
    || true
fi
echo "---REBOOT---"
if [ -f /var/run/reboot-required ]; then echo 1; else echo 0; fi
''';
  }

  @override
  FleetHostHealth parse(String stdout, String stderr, int exitCode) {
    final sections = _sections(stdout);
    final dash = const DashboardParser().parse(stdout);
    final nproc = int.tryParse((sections['NPROC'] ?? '').trim()) ?? 0;
    final pending = int.tryParse((sections['PENDING'] ?? '').trim().split('\n').first) ?? 0;
    final security =
        int.tryParse((sections['SECURITY'] ?? '').trim().split('\n').first) ?? 0;
    final reboot = (sections['REBOOT'] ?? '').trim().startsWith('1');
    final containers = countFleetContainerTrouble(
      (sections['CONTAINERS'] ?? '').split('\n'),
    );
    final highDisk = _highDiskMounts(sections['DISK'] ?? '');
    return FleetHostHealth(
      hostId: hostId,
      alias: alias,
      reachable: true,
      load1: dash.load1,
      nprocCores: nproc > 0 ? nproc : null,
      memPercent: dash.memUsedPercent,
      diskRootPercent: dash.diskRootPercent,
      highDiskMounts: highDisk,
      failedUnitCount: dash.failedUnitCount,
      pendingUpdates: pending,
      securityUpdates: security,
      containersDown: containers.down,
      containersUnhealthy: containers.unhealthy,
      uptime: dash.uptime,
      rebootRequired: reboot,
      fetchedAt: DateTime.now().toUtc(),
    );
  }

  static Map<String, String> _sections(String stdout) {
    final sections = <String, String>{};
    final re = RegExp(r'^---([A-Z0-9_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      final name = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      sections[name] = stdout.substring(start, end).trim();
    }
    return sections;
  }

  static List<String> _highDiskMounts(String df) {
    final out = <String>[];
    for (final line in df.split('\n').skip(1)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 7) {
        continue;
      }
      final mount = cols.last;
      final cap = cols[cols.length - 2].replaceAll('%', '');
      final pct = int.tryParse(cap) ?? 0;
      if (mount == '/') {
        continue;
      }
      if (pct > FleetHostHealth.diskWarnMount) {
        out.add('$mount:$pct%');
      }
    }
    return out;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 10);
}
