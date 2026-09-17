import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('fleet probe command is local-only: no dnf/apt/yum network package lists',
      () {
    final cmd = const FleetHealthProbe().command(
      HostFacts(
        osId: 'rocky',
        osVersionId: '9',
        init: InitSystem.systemd,
        systemdVersion: 252,
        pkg: PackageManager.dnf,
        fw: FirewallBackend.firewalld,
        hasJournald: true,
        journalReadable: true,
        arch: 'x86_64',
      ),
    );
    expect(cmd, contains('cat /proc/uptime'));
    expect(cmd, contains('df -PT'));
    expect(cmd, contains('systemctl list-units'));
    expect(cmd, isNot(contains('dnf ')));
    expect(cmd, isNot(contains('apt-get')));
    expect(cmd, isNot(contains('yum ')));
    expect(cmd, isNot(contains('check-update')));
    expect(cmd, isNot(contains('updateinfo')));
    expect(cmd, isNot(contains('---UPDATES---')));
    expect(cmd, isNot(contains('---SECURITY---')));
    // Packages screen still has network list helpers — fleet must not call them.
    expect(PackageCommands.listUpdatesForFleet(PackageManager.dnf),
        contains('dnf check-update'));
  });

  test('fleet probe timeout stays short for local reads', () {
    expect(const FleetHealthProbe().timeout.inSeconds, lessThanOrEqualTo(15));
    expect(const FleetHealthProbe().risk, RiskLevel.read);
  });

  test('fleet parse keeps local metrics when package sections are absent', () {
    const stdout = '''
---UPTIME---
3661.0 7000.0
---LOAD---
0.08 0.05 0.01 1/100 1
---NPROC---
1
---MEM---
MemTotal:       1000000 kB
MemAvailable:    920000 kB
---DISK---
Filesystem     Type 1024-blocks Used Available Capacity Mounted on
/dev/mapper/rlm-root xfs 17825792 4280340 13545452 24% /
---FAILED---
0
---FAILED_NAMES---
---CONTAINERS---
---REBOOT---
0
''';
    final health = const FleetHealthProbe(hostId: 'h', alias: 'rock')
        .parse(stdout, '', 0);
    expect(health.reachable, isTrue);
    expect(health.diskRootPercent, 24);
    expect(health.uptime, const Duration(seconds: 3661));
    expect(health.pendingUpdates, 0);
    expect(health.securityUpdates, 0);
  });

  test('partial empty sections do not invent zeros for disk or uptime', () {
    const stdout = '''
---UPTIME---
---LOAD---
0.01 0.01 0.01 1/1 1
---NPROC---
1
---MEM---
MemTotal:       1000000 kB
MemAvailable:    900000 kB
---DISK---
---FAILED---
0
---FAILED_NAMES---
---CONTAINERS---
---REBOOT---
0
''';
    final health = const FleetHealthProbe(hostId: 'h', alias: 'rock')
        .parse(stdout, '', 0);
    expect(health.reachable, isTrue);
    expect(health.diskRootPercent, isNull);
    expect(health.uptime, isNull);
    expect(health.diskLabel(), '—');
    expect(health.uptimeLabel(), '—');
  });
}
