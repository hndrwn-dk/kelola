import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';

const kelolaSudoersPath = '/etc/sudoers.d/kelola';
const kelolaSudoersMode = '0440';

enum KelolaSudoersGroup { packages, firewall, hostPower }

class KelolaSudoersSpec {
  const KelolaSudoersSpec({
    required this.user,
    required this.groups,
    required this.commands,
  });

  final String user;
  final Set<KelolaSudoersGroup> groups;
  final List<String> commands;

  String get path => kelolaSudoersPath;

  String get mode => kelolaSudoersMode;

  String get content {
    final buf = StringBuffer()
      ..writeln('# Kelola — managed sudoers drop-in')
      ..writeln('# path: $path  mode: $mode')
      ..writeln('# Never passwordless ALL or a shell.');
    if (commands.isEmpty) {
      return buf.toString();
    }
    buf.writeln();
    for (final cmd in commands) {
      buf.writeln('$user ALL=(root) NOPASSWD: $cmd');
    }
    return buf.toString();
  }

  String get contentHash => sha256.convert(utf8.encode(content)).toString();
}

/// Exact argv Kelola runs via `sudo -n` for the selected groups.
KelolaSudoersSpec buildKelolaSudoersSpec({
  required String user,
  required HostFacts facts,
  required Set<KelolaSudoersGroup> groups,
}) {
  final cmds = <String>[];
  if (groups.contains(KelolaSudoersGroup.packages)) {
    cmds.addAll(_packageCommands(facts.pkg));
  }
  if (groups.contains(KelolaSudoersGroup.firewall)) {
    cmds.addAll(_firewallCommands(facts.fw));
  }
  if (groups.contains(KelolaSudoersGroup.hostPower)) {
    cmds.addAll(const ['/usr/sbin/reboot', '/usr/sbin/poweroff']);
  }
  return KelolaSudoersSpec(user: user, groups: groups, commands: cmds);
}

Set<KelolaSudoersGroup> defaultKelolaSudoersGroups(HostFacts facts) {
  final out = <KelolaSudoersGroup>{KelolaSudoersGroup.hostPower};
  if (facts.pkg != PackageManager.unknown) {
    out.add(KelolaSudoersGroup.packages);
  }
  if (facts.fw != FirewallBackend.none) {
    out.add(KelolaSudoersGroup.firewall);
  }
  return out;
}

List<String> _packageCommands(PackageManager pkg) {
  switch (pkg) {
    case PackageManager.dnf:
      return const [
        '/usr/bin/dnf --color=never check-update --refresh',
        '/usr/bin/dnf --color=never --cacheonly updateinfo list security',
        '/usr/bin/dnf upgrade -y',
        '/usr/bin/dnf upgrade -y *',
        '/usr/bin/dnf upgrade -y --security',
      ];
    case PackageManager.yum:
      return const [
        '/usr/bin/yum --color=never check-update --refresh',
        '/usr/bin/yum --color=never --cacheonly updateinfo list security',
        '/usr/bin/yum update -y',
        '/usr/bin/yum update -y *',
        '/usr/bin/yum update -y --security',
      ];
    case PackageManager.apt:
      return const [
        '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold upgrade',
        '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold '
            'install --only-upgrade *',
        '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold '
            '-o Dir::Etc::SourceList=/etc/apt/security.sources.list upgrade',
      ];
    case PackageManager.zypper:
      return const [
        '/usr/bin/zypper --non-interactive update',
        '/usr/bin/zypper --non-interactive update *',
        '/usr/bin/zypper --non-interactive patch --category security',
      ];
    case PackageManager.apk:
      return const ['/sbin/apk upgrade', '/sbin/apk add -u *'];
    case PackageManager.pacman:
      return const [
        '/usr/bin/pacman -Syu --noconfirm',
        '/usr/bin/pacman -S --noconfirm *',
      ];
    case PackageManager.unknown:
      return const [];
  }
}

List<String> _firewallCommands(FirewallBackend fw) {
  switch (fw) {
    case FirewallBackend.firewalld:
      return const ['/usr/bin/firewall-cmd'];
    case FirewallBackend.ufw:
      return const ['/usr/sbin/ufw'];
    case FirewallBackend.nftables:
      return const ['/usr/sbin/nft'];
    case FirewallBackend.iptables:
      return const ['/usr/sbin/iptables-save'];
    case FirewallBackend.none:
      return const [];
  }
}
