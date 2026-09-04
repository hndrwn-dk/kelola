import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  const facts = HostFacts(
    osId: 'debian',
    osVersionId: '12',
    prettyName: 'Debian',
    init: InitSystem.systemd,
    systemdVersion: 252,
    pkg: PackageManager.apt,
    fw: FirewallBackend.none,
    hasJournald: true,
    journalReadable: true,
    arch: 'amd64',
    nprocCores: 4,
  );

  test('FleetHealthProbe is read-only with 10s timeout', () {
    const p = FleetHealthProbe();
    expect(p.risk, RiskLevel.read);
    expect(p.timeout, const Duration(seconds: 10));
  });

  test('tile command has no dual /proc/stat sleep', () {
    final cmd = const FleetHealthProbe(hostId: 'h1', alias: 'web').command(facts);
    expect(cmd, isNot(contains('sleep')));
    expect(cmd, isNot(contains('---STAT1---')));
    expect(cmd, isNot(contains('---STAT2---')));
    expect(cmd, contains('---LOAD---'));
    expect(cmd, contains('---MEM---'));
    expect(cmd, contains('---DISK---'));
    expect(cmd, contains('---PENDING---'));
    expect(cmd, contains('---SECURITY---'));
    expect(cmd, contains('---CONTAINERS---'));
    expect(cmd, contains('---REBOOT---'));
    expect(cmd, contains('---NPROC---'));
  });

  test('parses expanded fleet health without inventing CPU percent', () {
    const stdout = '''
---UPTIME---
3661.0 7000.0
---LOAD---
2.00 1.50 1.00 2/100 1
---NPROC---
4
---MEM---
MemTotal:       1000000 kB
MemAvailable:    400000 kB
---DISK---
Filesystem     Type 1024-blocks Used Available Capacity Mounted on
/dev/sda1      ext4     1000000 500000    500000      50% /
/dev/sdb1      ext4     1000000 900000    100000      91% /var
---FAILED---
1
---FAILED_NAMES---
nginx.service
---PENDING---
5
---SECURITY---
2
---CONTAINERS---
exited	Exited (1) 3 hours ago	bad
exited	Exited (0) 1 day ago	okjob
running	Up 2 days (unhealthy)	db
restarting	Restarting (1) 10 seconds ago	api
---REBOOT---
1
''';
    final health = const FleetHealthProbe(hostId: 'h1', alias: 'web')
        .parse(stdout, '', 0);
    expect(health.reachable, isTrue);
    expect(health.load1, 2.0);
    expect(health.nprocCores, 4);
    expect(health.loadRatio, 0.5);
    expect(health.memPercent, 60);
    expect(health.diskRootPercent, 50);
    expect(health.highDiskMounts, ['/var:91%']);
    expect(health.failedUnitCount, 1);
    expect(health.pendingUpdates, 5);
    expect(health.securityUpdates, 2);
    expect(health.containersDown, 2);
    expect(health.containersUnhealthy, 1);
    expect(health.rebootRequired, isTrue);
    expect(health.uptime.inSeconds, 3661);
  });
}
