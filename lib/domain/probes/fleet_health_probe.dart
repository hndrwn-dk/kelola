import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Single batched read for fleet tiles. Local-only: no package repo network.
///
/// Pending/security update counts come from the Packages screen cache (or are
/// omitted), never from this probe. Partial section failures leave other
/// metrics intact; unknown values stay null rather than lying zeros.
class FleetHealthProbe extends Probe<FleetHostHealth> {
  const FleetHealthProbe({
    this.hostId = '',
    this.alias = '',
    this.pkg = PackageManager.unknown,
  });

  final String hostId;
  final String alias;

  /// Retained for call-site compatibility; unused — fleet no longer lists pkgs.
  final PackageManager pkg;

  @override
  String get auditTitle => 'Fleet health';

  @override
  String command(HostFacts facts) {
    // Treat unknown init as systemd-capable: Fleet refresh often runs without
    // cached HostFacts (undiscovered), and skipping systemctl here made tiles
    // stay green while the host dashboard correctly showed failed units.
    final failed = facts.init == InitSystem.openrc ||
            facts.init == InitSystem.sysvinit
        ? r'''
echo "---FAILED---"
echo 0
echo "---FAILED_NAMES---"
'''
        : r'''
echo "---FAILED---"
systemctl list-units --type=service --state=failed --no-legend --plain --no-pager 2>/dev/null | wc -l
echo "---FAILED_NAMES---"
systemctl list-units --type=service --state=failed --no-legend --plain --no-pager 2>/dev/null | awk '{print $1}'
''';
    final nproc = facts.nprocCores != null
        ? 'echo "---NPROC---"\necho ${facts.nprocCores}\n'
        : r'''
echo "---NPROC---"
nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 0
''';
    // Local reads only. Never dnf/apt/yum — those hit the network and can
    // timeout the whole probe on Rocky (and mark the host unreachable).
    return '''
LC_ALL=C
echo "---UPTIME---"
cat /proc/uptime 2>/dev/null || true
echo "---LOAD---"
cat /proc/loadavg 2>/dev/null || true
$nproc
echo "---MEM---"
cat /proc/meminfo 2>/dev/null || true
echo "---DISK---"
df -PT 2>/dev/null || true
$failed
echo "---CONTAINERS---"
# Unprivileged docker/podman only; never escalate on fleet refresh.
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true
elif command -v podman >/dev/null 2>&1; then
  uid=\$(id -u)
  if [ -z "\${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/\$uid" ]; then
    export XDG_RUNTIME_DIR="/run/user/\$uid"
  fi
  podman ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true
  sock=/run/podman/podman.sock
  if [ -S "\$sock" ] && [ -r "\$sock" ]; then
    podman --remote --url "unix://\$sock" ps -a --format '{{.State}}\t{{.Status}}\t{{.Names}}' 2>/dev/null || true
  fi
fi
echo "---REBOOT---"
if [ -f /var/run/reboot-required ]; then echo 1; else echo 0; fi
''';
  }

  @override
  FleetHostHealth parse(String stdout, String stderr, int exitCode) {
    final sections = _sections(stdout);
    final uptime = DashboardParser.parseUptime(sections['UPTIME'] ?? '');
    final disk = DashboardParser.parseDiskRoot(sections['DISK'] ?? '');
    final dash = const DashboardParser().parse(stdout);
    final nprocRaw = int.tryParse((sections['NPROC'] ?? '').trim());
    final nproc = (nprocRaw != null && nprocRaw > 0) ? nprocRaw : null;
    final reboot = (sections['REBOOT'] ?? '').trim().startsWith('1');
    final containers = countFleetContainerTrouble(
      (sections['CONTAINERS'] ?? '').split('\n'),
    );
    final highDisk = _highDiskMounts(sections['DISK'] ?? '');
    // Update counts are not read here — callers keep Packages-cache values.
    return FleetHostHealth(
      hostId: hostId,
      alias: alias,
      reachable: true,
      load1: dash.load1,
      nprocCores: nproc,
      memPercent: dash.memUsedPercent,
      diskRootPercent: disk.known ? disk.percent : null,
      highDiskMounts: highDisk,
      failedUnitCount: dash.failedUnitCount,
      pendingUpdates: 0,
      securityUpdates: 0,
      containersDown: containers.down,
      containersUnhealthy: containers.unhealthy,
      uptime: uptime,
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
      final pct = int.tryParse(cap);
      if (pct == null) {
        continue;
      }
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
  Duration get timeout => const Duration(seconds: 15);
}
