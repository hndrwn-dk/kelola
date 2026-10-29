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
}
