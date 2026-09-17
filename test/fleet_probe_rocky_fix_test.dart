import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/dashboard_parser.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/hosts/host_probe_outcome.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  const rockyFacts = HostFacts(
    osId: 'rocky',
    osVersionId: '9.8',
    prettyName: 'Rocky Linux 9.8',
    init: InitSystem.systemd,
    systemdVersion: 252,
    pkg: PackageManager.dnf,
    fw: FirewallBackend.firewalld,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
    nprocCores: 1,
  );

  test('fleet probe never runs dnf (avoids Rocky network timeout)', () {
    final cmd = const FleetHealthProbe().command(rockyFacts);
    expect(cmd, isNot(contains('dnf ')));
    expect(cmd, isNot(contains('check-update')));
    expect(cmd, isNot(contains('---UPDATES---')));
    expect(cmd, isNot(contains('---SECURITY---')));
    expect(cmd, contains('cat /proc/uptime'));
    expect(cmd, contains('df -PT'));
  });

  test('FleetHealthProbe timeout fits local reads', () {
    expect(const FleetHealthProbe().timeout.inSeconds, lessThanOrEqualTo(15));
    expect(const FleetHealthProbe().risk, RiskLevel.read);
  });

  test('Rocky mapper root df parses disk percent; empty df is unknown not zero',
      () {
    const rockyDf = '''
Filesystem                   Type 1024-blocks    Used Available Capacity Mounted on
/dev/mapper/rlm-root         xfs    17825792  4280340  13545452      24% /
tmpfs                        tmpfs   1982344        0   1982344       0% /dev/shm
''';
    final disk = DashboardParser.parseDiskRoot(rockyDf);
    expect(disk.percent, 24);
    expect(disk.totalKib, greaterThan(0));
    expect(disk.known, isTrue);

    final missing = DashboardParser.parseDiskRoot('Filesystem Type\n');
    expect(missing.known, isFalse);
    expect(missing.percent, isNull);

    final emptyUp = DashboardParser.parseUptime('');
    expect(emptyUp, isNull);
    final up = DashboardParser.parseUptime('3661.0 7000.0');
    expect(up, const Duration(seconds: 3661));
  });

  test('fleet tile shows em dash for unknown disk and uptime, never lying zeros',
      () {
    final unknown = FleetHostHealth(
      hostId: 'h',
      alias: 'east-rock-uat',
      reachable: true,
      load1: 0.01,
      nprocCores: 1,
      memPercent: 8,
      diskRootPercent: null,
      failedUnitCount: 0,
      pendingUpdates: 0,
      uptime: null,
      rebootRequired: false,
      fetchedAt: DateTime.utc(2026, 9, 16),
      outcome: HostProbeOutcome.healthy,
    );
    final metrics = unknown.tileMetrics();
    expect(metrics.map((m) => m.label), containsAll(['disk', 'up']));
    expect(
      metrics.firstWhere((m) => m.label == 'disk').value,
      isNot(contains('0%')),
    );
    expect(metrics.firstWhere((m) => m.label == 'disk').value, '—');
    expect(metrics.firstWhere((m) => m.label == 'up').value, '—');
  });

  test('timed-out fleet probe is not a hard unreachable for host attention', () {
    expect(isConnectionFailureOutcome(HostProbeOutcome.timedOut), isFalse);
    expect(shouldMarkHostUnreachable(HostProbeOutcome.timedOut), isFalse);
    expect(shouldMarkHostUnreachable(HostProbeOutcome.refused), isTrue);
    expect(shouldMarkHostUnreachable(HostProbeOutcome.unreachable), isTrue);
    expect(hostProbeStateLabel(HostProbeOutcome.timedOut), 'timed out');
  });

  test('parses Rocky fleet stdout without package sections', () {
    const stdout = '''
---UPTIME---
7320.5 14000.0
---LOAD---
0.00 0.01 0.05 1/120 1
---NPROC---
1
---MEM---
MemTotal:        8000000 kB
MemAvailable:    7360000 kB
MemFree:         7000000 kB
Buffers:           10000 kB
Cached:           300000 kB
---DISK---
Filesystem                   Type 1024-blocks    Used Available Capacity Mounted on
/dev/mapper/rlm-root         xfs    17825792  4280340  13545452      24% /
---FAILED---
0
---FAILED_NAMES---
---CONTAINERS---
---REBOOT---
0
''';
    final health = const FleetHealthProbe(
      hostId: 'h',
      alias: 'rock',
      pkg: PackageManager.dnf,
    ).parse(stdout, '', 0);
    expect(health.reachable, isTrue);
    expect(health.diskRootPercent, 24);
    expect(health.uptime, const Duration(seconds: 7320));
    expect(health.uptimeLabel(), isNot('0m'));
    expect(health.pendingUpdates, 0);
    expect(health.securityUpdates, 0);
  });

  test('fleet package list commands stay available for Packages screen refresh',
      () {
    expect(PackageCommands.listUpdates(PackageManager.dnf), contains('--refresh'));
    expect(
      PackageCommands.listUpdatesForFleet(PackageManager.dnf),
      isNot(contains('--refresh')),
    );
  });
}
