import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';

HostFacts facts({
  PackageManager pkg = PackageManager.dnf,
  FirewallBackend fw = FirewallBackend.firewalld,
}) {
  return HostFacts(
    osId: 'rocky',
    osVersionId: '9',
    init: InitSystem.systemd,
    systemdVersion: 252,
    pkg: pkg,
    fw: fw,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
  );
}

void main() {
  test('rocky dnf+firewalld full set matches Kelola runtime argv', () {
    final spec = buildKelolaSudoersSpec(
      user: 'hendr',
      facts: facts(),
      groups: {
        KelolaSudoersGroup.packages,
        KelolaSudoersGroup.firewall,
        KelolaSudoersGroup.hostPower,
      },
    );
    expect(spec.path, '/etc/sudoers.d/kelola');
    expect(spec.mode, '0440');
    expect(spec.content, contains('hendr ALL=(root) NOPASSWD:'));
    expect(
      spec.content,
      contains('/usr/bin/dnf --color=never check-update --refresh'),
    );
    expect(
      spec.content,
      contains(
        '/usr/bin/dnf --color=never --cacheonly updateinfo list security',
      ),
    );
    expect(spec.content, contains('/usr/bin/dnf upgrade -y'));
    expect(spec.content, contains('/usr/bin/dnf upgrade -y *'));
    expect(spec.content, contains('/usr/bin/dnf upgrade -y --security'));
    expect(spec.content, contains('/usr/bin/firewall-cmd'));
    expect(spec.content, contains('/usr/sbin/reboot'));
    expect(spec.content, contains('/usr/sbin/poweroff'));
    expect(spec.commands.any((c) => c == 'ALL'), isFalse);
    expect(spec.content, isNot(contains('/bin/sh')));
    expect(
      spec.content,
      isNot(contains('NOPASSWD: /usr/bin/dnf check-update --refresh')),
    );
  });

  test('apt+ufw packages omit unprivileged list; firewall is ufw binary', () {
    final spec = buildKelolaSudoersSpec(
      user: 'hendra',
      facts: facts(pkg: PackageManager.apt, fw: FirewallBackend.ufw),
      groups: {
        KelolaSudoersGroup.packages,
        KelolaSudoersGroup.firewall,
      },
    );
    expect(spec.content, contains('/usr/bin/apt-get'));
    expect(spec.content, contains('/usr/sbin/ufw'));
    expect(spec.content, isNot(contains('/usr/bin/dnf')));
    expect(spec.content, isNot(contains('/usr/bin/firewall-cmd')));
  });

  test('packages-only omits firewall and host power', () {
    final spec = buildKelolaSudoersSpec(
      user: 'hendr',
      facts: facts(),
      groups: {KelolaSudoersGroup.packages},
    );
    expect(spec.content, contains('dnf'));
    expect(spec.content, isNot(contains('firewall-cmd')));
    expect(spec.content, isNot(contains('reboot')));
  });

  test('empty groups yields empty body with header comment only', () {
    final spec = buildKelolaSudoersSpec(
      user: 'hendr',
      facts: facts(),
      groups: {},
    );
    expect(spec.content.trim(), startsWith('#'));
    expect(spec.commands, isEmpty);
  });

  test('default groups are the full available set for rocky', () {
    final groups = defaultKelolaSudoersGroups(facts());
    expect(
      groups,
      {
        KelolaSudoersGroup.packages,
        KelolaSudoersGroup.firewall,
        KelolaSudoersGroup.hostPower,
        KelolaSudoersGroup.services,
        KelolaSudoersGroup.processes,
      },
    );
  });

  test('default groups omit packages and firewall when facts lack them', () {
    final groups = defaultKelolaSudoersGroups(
      facts(pkg: PackageManager.unknown, fw: FirewallBackend.none),
    );
    expect(
      groups,
      containsAll(<KelolaSudoersGroup>{
        KelolaSudoersGroup.hostPower,
        KelolaSudoersGroup.processes,
      }),
    );
    expect(groups, isNot(contains(KelolaSudoersGroup.packages)));
    expect(groups, isNot(contains(KelolaSudoersGroup.firewall)));
  });

  group('services and processes', () {
    final spec = buildKelolaSudoersSpec(
      user: 'hendr',
      facts: facts(),
      groups: const {
        KelolaSudoersGroup.services,
        KelolaSudoersGroup.processes,
      },
    );

    test('covers what Kelola runs through sudo', () {
      for (final verb in ['start', 'stop', 'restart', 'reload']) {
        expect(
          spec.commands,
          contains('/usr/bin/systemctl $verb [a-zA-Z0-9]*'),
        );
      }
      expect(spec.commands, contains('/usr/bin/kill -s TERM [0-9]*'));
      expect(spec.commands, contains('/usr/bin/kill -s KILL [0-9]*'));
    });

    test('never allows unit file installs, a bare binary or a shell', () {
      for (final bad in ['enable', 'disable', 'link', 'edit', 'mask', 'daemon-']) {
        expect(spec.content, isNot(contains('systemctl $bad')), reason: bad);
      }
      expect(spec.commands, isNot(contains('/usr/bin/systemctl')));
      expect(spec.commands, isNot(contains('/usr/bin/systemctl *')));
      expect(spec.content, isNot(contains('/bin/sh')));
      expect(spec.content, isNot(contains('NOPASSWD: ALL')));
    });

    test('the first argument cannot begin as an option or a path', () {
      for (final cmd in spec.commands.where((c) => c.contains('systemctl'))) {
        expect(cmd, endsWith(' [a-zA-Z0-9]*'));
      }
    });

    test('only systemd hosts get service rules', () {
      final openrc = HostFacts.undiscovered.copyWith(init: InitSystem.openrc);
      expect(
        defaultKelolaSudoersGroups(openrc),
        isNot(contains(KelolaSudoersGroup.services)),
      );
      expect(
        buildKelolaSudoersSpec(
          user: 'u',
          facts: openrc,
          groups: const {KelolaSudoersGroup.services},
        ).commands,
        isEmpty,
      );
    });
  });
}
