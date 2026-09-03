import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/packages/package_parser.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/probes/package_apply_probe.dart';
import 'package:kelola/domain/probes/package_list_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

String fixture(String name) =>
    File('test/fixtures/packages/$name').readAsStringSync();

HostFacts factsOf(PackageManager pkg) {
  return HostFacts(
    osId: 'test',
    osVersionId: '1',
    init: InitSystem.systemd,
    systemdVersion: 255,
    pkg: pkg,
    fw: FirewallBackend.none,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
  );
}

void main() {
  const parser = PackageParser();

  test('list commands come from HostFacts.pkg, not command -v', () {
    const probe = PackageListProbe();
    final apt = probe.command(factsOf(PackageManager.apt));
    expect(apt, contains('apt-get -s upgrade'));
    expect(apt, contains('Dir::Etc::SourceList=/etc/apt/security.sources.list'));
    expect(apt, isNot(contains('command -v apt')));
    expect(apt, isNot(contains('command -v dnf')));
    expect(apt, contains('---PKG---'));
    expect(apt, contains('echo apt'));

    final dnf = probe.command(factsOf(PackageManager.dnf));
    expect(dnf, contains('dnf check-update --refresh'));
    expect(dnf, contains('dnf updateinfo list security'));
    expect(dnf, contains('echo dnf'));

    final zypper = probe.command(factsOf(PackageManager.zypper));
    expect(zypper, contains('zypper -q lu'));
    expect(zypper, contains('zypper lp --category security'));

    final apk = probe.command(factsOf(PackageManager.apk));
    expect(apk, contains("apk version -l '<'"));
    expect(apk, contains('echo N/A'));

    final pacman = probe.command(factsOf(PackageManager.pacman));
    expect(pacman, contains('pacman -Qu'));
    expect(pacman, contains('checkupdates'));

    final yum = probe.command(factsOf(PackageManager.yum));
    expect(yum, contains('yum check-update'));
    expect(yum, contains('yum updateinfo list security'));
  });

  test('apk and pacman do not claim a security filter', () {
    expect(PackageCommands.securitySupported(PackageManager.apk), isFalse);
    expect(PackageCommands.securitySupported(PackageManager.pacman), isFalse);
    expect(PackageCommands.securitySupported(PackageManager.apt), isTrue);
    expect(PackageCommands.securitySupported(PackageManager.dnf), isTrue);
  });

  test('parses apt-get -s upgrade and flags Debian-Security as security', () {
    final snap = parser.parse(
      manager: PackageManager.apt,
      stdout: fixture('apt_upgrade.txt'),
    );
    expect(snap.updates.map((u) => u.name),
        containsAll(['libssl3', 'openssl', 'curl', 'tzdata']));
    expect(
      snap.updates.firstWhere((u) => u.name == 'openssl').security,
      isTrue,
    );
    expect(
      snap.updates.firstWhere((u) => u.name == 'tzdata').security,
      isFalse,
    );
    expect(
      snap.updates.firstWhere((u) => u.name == 'openssl').currentVersion,
      '3.0.11-1~deb12u2',
    );
  });

  test('merges security-only apt list onto updates', () {
    final stdout = '''
---PKG---
apt
---UPDATES---
${fixture('apt_upgrade.txt')}
---SECURITY---
${fixture('apt_security.txt')}
---REBOOT---
FILE
linux-image-6.1.0
''';
    final snap = parser.parse(manager: PackageManager.apt, stdout: stdout);
    expect(snap.updates.firstWhere((u) => u.name == 'curl').security, isTrue);
    expect(snap.rebootRequired, isTrue);
    expect(snap.rebootReasons, contains('linux-image-6.1.0'));
  });

  test('parses dnf check-update and updateinfo security', () {
    final stdout = '''
---UPDATES---
${fixture('dnf_check_update.txt')}
---SECURITY---
${fixture('dnf_security.txt')}
---REBOOT---
NEEDS_RESTARTING_R:1
''';
    final snap = parser.parse(manager: PackageManager.dnf, stdout: stdout);
    expect(snap.updates.map((u) => u.name), containsAll(['openssl', 'kernel', 'curl']));
    expect(snap.updates.firstWhere((u) => u.name == 'openssl').security, isTrue);
    expect(snap.rebootRequired, isTrue);
  });

  test('parses zypper, apk, pacman, yum', () {
    expect(
      parser
          .parse(manager: PackageManager.zypper, stdout: fixture('zypper_lu.txt'))
          .updates
          .map((u) => u.name),
      containsAll(['openssl', 'curl']),
    );
    final apk = parser.parse(
      manager: PackageManager.apk,
      stdout: fixture('apk_version.txt'),
    );
    expect(apk.updates.first.name, 'busybox');
    expect(apk.updates.first.currentVersion, '1.36.1-r0');
    expect(apk.updates.first.candidateVersion, '1.36.1-r15');
    final pac = parser.parse(
      manager: PackageManager.pacman,
      stdout: fixture('pacman_qu.txt'),
    );
    expect(pac.updates.first.name, 'linux');
    expect(pac.updates.first.currentVersion, '6.6.1.arch1-1');
    expect(
      parser
          .parse(manager: PackageManager.yum, stdout: fixture('yum_check_update.txt'))
          .updates
          .map((u) => u.name),
      containsAll(['openssl', 'bash']),
    );
  });

  test('chips are filters with counts and empty copy', () {
    final snap = parser.parse(
      manager: PackageManager.apt,
      stdout: fixture('apt_upgrade.txt'),
    );
    final counts = PackageListCounts.from(snap);
    expect(packageListChipLabel(PackageListFilter.security, counts),
        'Security ${counts.security}');
    expect(packageListChipLabel(PackageListFilter.all, counts), 'All ${counts.all}');
    expect(defaultPackageFilter(snap), PackageListFilter.security);
    expect(
      visiblePackageUpdates(snap, PackageListFilter.security).every((u) => u.security),
      isTrue,
    );
    expect(packageListEmptyCopy(PackageListFilter.security), 'No security updates.');
  });

  test('apply is destructive, uses HostFacts.pkg, never auto-runs', () {
    const probe = PackageApplyProbe(
      names: ['openssl', 'libssl3', 'curl'],
      securityOnly: true,
      manager: PackageManager.apt,
    );
    expect(probe.risk, RiskLevel.destructive);
    expect(probe.auditTitle, 'Applied 3 security updates');
    expect(
      probe.command(factsOf(PackageManager.apt)),
      contains('/usr/bin/apt-get'),
    );
    expect(
      probe.command(factsOf(PackageManager.apt)),
      isNot(contains('unattended-upgrade')),
    );
    expect(
      const PackageApplyProbe(
        names: ['linux', 'pacman'],
        securityOnly: false,
        manager: PackageManager.pacman,
      ).auditTitle,
      'Applied 2 updates',
    );
  });

  test('list probe parse reads PKG from the script echo, not a second detection',
      () {
    const probe = PackageListProbe();
    final out = '''
---PKG---
apt
---UPDATES---
${fixture('apt_upgrade.txt')}
---SECURITY---
---REBOOT---
''';
    final snap = probe.parse(out, '', 0);
    expect(snap.manager, PackageManager.apt);
    expect(snap.updates, isNotEmpty);
  });
}
