import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('FleetHealthProbe is read-only with 10s timeout', () {
    const p = FleetHealthProbe();
    expect(p.risk, RiskLevel.read);
    expect(p.timeout, const Duration(seconds: 10));
  });

  test('parses dashboard sections plus pending count', () {
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
    );
    final cmd = const FleetHealthProbe(hostId: 'h1', alias: 'web').command(facts);
    expect(cmd, contains('---PENDING---'));
    expect(cmd, contains('---LOAD---'));

    const stdout = '''
---UPTIME---
100.0 200.0
---LOAD---
1.25 1.00 0.75 2/100 1
---STAT1---
cpu  1 2 3 4
---STAT2---
cpu  2 3 4 5
---MEM---
MemTotal:       1000000 kB
MemAvailable:    500000 kB
---DISK---
Filesystem     Type 1024-blocks Used Available Capacity Mounted on
/dev/sda1      ext4     1000000 900000    100000      90% /
---FAILED---
2
---FAILED_NAMES---
nginx.service
sshd.service
---PENDING---
7
''';
    final health = const FleetHealthProbe(hostId: 'h1', alias: 'web')
        .parse(stdout, '', 0);
    expect(health.reachable, isTrue);
    expect(health.load1, 1.25);
    expect(health.diskRootPercent, 90);
    expect(health.failedUnitCount, 2);
    expect(health.pendingUpdates, 7);
    expect(health.alias, 'web');
  });
}
