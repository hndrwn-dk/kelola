import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';

const kelolaSudoersPath = '/etc/sudoers.d/kelola';
const kelolaSudoersMode = '0440';

enum KelolaSudoersGroup { packages, firewall, hostPower, services, processes }

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
      ..writeln('# Never passwordless ALL or a shell.')
      ..writeln('# Positive rules only.');
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

/// Commands Kelola runs via `sudo -n` for the selected groups, as positive
/// rules only.
///
/// A `!` rule cannot be used: sudo applies the last match and this file is
/// read last, so a refusal here also denies the admin's own password sudo.
///
/// Fixed commands are exact rules, which every sudo accepts. A command with a
/// value that varies needs [SudoFlavor.supportsArgRegex]. Sudo-rs and older
/// classic sudo have no safe way to say "one package name": their only other
/// wildcard is a trailing `*`, which also takes `-c /tmp/evil.conf`. On those
/// hosts the rule is left out and `sudo -n` fails as it would with no rule.
KelolaSudoersSpec buildKelolaSudoersSpec({
  required String user,
  required HostFacts facts,
  required Set<KelolaSudoersGroup> groups,
  required SudoFlavor sudo,
}) {
  final cmds = <String>[];
  final regex = sudo.supportsArgRegex;
  if (groups.contains(KelolaSudoersGroup.packages)) {
    cmds.addAll(_packageCommands(facts.pkg));
    if (regex) {
      cmds.addAll(_packageRegexCommands(facts.pkg));
    }
  }
  if (groups.contains(KelolaSudoersGroup.firewall)) {
    cmds.addAll(_firewallCommands(facts.fw));
    if (regex) {
      cmds.addAll(_firewallRegexCommands(facts.fw));
    }
  }
  if (groups.contains(KelolaSudoersGroup.hostPower)) {
    cmds.addAll(const ['/usr/sbin/reboot ""', '/usr/sbin/poweroff ""']);
  }
  if (regex && groups.contains(KelolaSudoersGroup.services)) {
    cmds.addAll(_serviceRegexCommands(facts.init));
  }
  if (regex && groups.contains(KelolaSudoersGroup.processes)) {
    cmds.addAll(_processRegexCommands);
  }
  return KelolaSudoersSpec(user: user, groups: groups, commands: cmds);
}

/// Groups that have at least one rule on this host. Services and Processes
/// are all variable values, so they drop out without regex support.
Set<KelolaSudoersGroup> defaultKelolaSudoersGroups(
  HostFacts facts, {
  required SudoFlavor sudo,
}) {
  final out = <KelolaSudoersGroup>{KelolaSudoersGroup.hostPower};
  if (facts.pkg != PackageManager.unknown) {
    out.add(KelolaSudoersGroup.packages);
  }
  if (facts.fw != FirewallBackend.none) {
    out.add(KelolaSudoersGroup.firewall);
  }
  if (sudo.supportsArgRegex) {
    if (_serviceRegexCommands(facts.init).isNotEmpty) {
      out.add(KelolaSudoersGroup.services);
    }
    out.add(KelolaSudoersGroup.processes);
  }
  return out;
}

/// Shown before install when this host's sudo cannot take the regex rules.
String? kelolaSudoersTierNote(SudoFlavor sudo) {
  if (sudo.supportsArgRegex) {
    return null;
  }
  return 'This host\'s sudo cannot limit a value that changes, so upgrading '
      'one package, changing a firewall port, service actions and process '
      'signals still need your own sudo.';
}

const kelolaSudoRulesOutdatedCopy =
    'Kelola sudo rules are outdated. Re-run Enable Kelola sudo.';

/// Rule text with sudo's listing escapes removed. Classic sudo keeps `\:` and
/// adds `\=`, and before 1.9.10 also prints `""` as `\"\"`. Sudo-rs prints none.
String normalizeSudoRule(String rule) => rule.replaceAllMapped(
      RegExp(r'\\([:="])'),
      (m) => m[1]!,
    );

const _kelolaBinaries = {
  '/usr/bin/dnf',
  '/usr/bin/yum',
  '/usr/bin/apt-get',
  '/usr/bin/zypper',
  '/sbin/apk',
  '/usr/bin/pacman',
  '/usr/bin/firewall-cmd',
  '/usr/sbin/ufw',
  '/usr/sbin/nft',
  '/usr/sbin/iptables-save',
  '/usr/sbin/reboot',
  '/usr/sbin/poweroff',
  '/usr/bin/systemctl',
  '/usr/bin/kill',
};

/// Commands a `sudo -n -l` listing grants without a password.
List<String> parseSudoListing(String listing) {
  final out = <String>[];
  for (final line in listing.split('\n')) {
    const tag = 'NOPASSWD:';
    final at = line.indexOf(tag);
    if (at < 0) {
      continue;
    }
    final rule = line.substring(at + tag.length).trim();
    if (rule.isNotEmpty) {
      out.add(rule);
    }
  }
  return out;
}

/// Whether a host's listed NOPASSWD rules fall short of [spec] or go past it.
///
/// A rule of ours that is missing counts, and so does a listed rule that takes
/// arbitrary arguments or a refusal: the bare binaries, `*` and `!` of earlier
/// versions. An extra exact rule does not count, because that is the one
/// command a sudo hint told the admin to add. No listed Kelola rule at all
/// means Kelola sudo was never enabled here, which is not outdated.
bool kelolaSudoRulesOutdated({
  required List<String> listed,
  required KelolaSudoersSpec spec,
}) {
  final ours = <String>[];
  for (final raw in listed) {
    final rule = normalizeSudoRule(raw);
    final binary = rule.split(' ').first.replaceFirst('!', '');
    if (_kelolaBinaries.contains(binary)) {
      ours.add(rule);
    }
  }
  if (ours.isEmpty) {
    return false;
  }
  final expected = spec.commands.map(normalizeSudoRule).toSet();
  if (!expected.every(ours.contains)) {
    return true;
  }
  return ours.any((rule) {
    if (expected.contains(rule)) {
      return false;
    }
    final wide = rule.startsWith('!') ||
        !rule.contains(' ') ||
        rule.contains('*') ||
        rule.contains('[');
    return wide;
  });
}

/// Any character a package name may hold, less [without]. Spelled out because
/// ERE has no way to subtract from a range.
String _nameClass([String without = '']) {
  const letters = 'abcdefghijklmnopqrstuvwxyz._+';
  final keep = letters.split('').where((c) => !without.contains(c)).join();
  final dash = without.contains('-') ? '' : '-';
  return '[${keep}A-Z0-9$dash]';
}

/// One package name: no leading `-`, and no `/`, `:`, `=`, `@` or space, which
/// select files, URLs, versions and extra arguments.
///
/// ERE has no lookahead, so "does not end in [notEnding]" is written out: the
/// name differs from it at the last character, or at the one before, and so on.
/// This keeps `rpm` and `librpm` while refusing `evil.rpm`, which dnf would
/// install from the working directory. [neverLast] refuses a final character.
String _packageName({String notEnding = '', String neverLast = ''}) {
  const first = '[a-zA-Z0-9]';
  const any = '[a-zA-Z0-9._+-]';
  if (notEnding.isEmpty && neverLast.isEmpty) {
    return '$first$any*';
  }
  final endings = <String>[];
  for (var i = notEnding.length; i >= 1; i--) {
    final tail = notEnding.substring(i);
    final differs = notEnding[i - 1] + (tail.isEmpty ? neverLast : '');
    endings.add('($any*${_nameClass(differs)})?$tail');
  }
  return '$first(${endings.join('|')})';
}

List<String> _packageCommands(PackageManager pkg) {
  switch (pkg) {
    case PackageManager.dnf:
      return const [
        '/usr/bin/dnf --color=never check-update --refresh',
        '/usr/bin/dnf --color=never --cacheonly updateinfo list security',
        '/usr/bin/dnf upgrade -y',
        '/usr/bin/dnf upgrade -y --security',
      ];
    case PackageManager.yum:
      return const [
        '/usr/bin/yum --color=never check-update --refresh',
        '/usr/bin/yum --color=never --cacheonly updateinfo list security',
        '/usr/bin/yum update -y',
        '/usr/bin/yum update -y --security',
      ];
    case PackageManager.apt:
      // `:` ends a sudoers command unless escaped.
      return const [
        r'/usr/bin/apt-get -y -o Dpkg\:\:Options\:\:=--force-confold upgrade',
        r'/usr/bin/apt-get -y -o Dpkg\:\:Options\:\:=--force-confold '
            r'-o Dir\:\:Etc\:\:SourceList=/etc/apt/security.sources.list upgrade',
      ];
    case PackageManager.zypper:
      return const [
        '/usr/bin/zypper --non-interactive update',
        '/usr/bin/zypper --non-interactive patch --category security',
      ];
    case PackageManager.apk:
      return const ['/sbin/apk upgrade'];
    case PackageManager.pacman:
      return const ['/usr/bin/pacman -Syu --noconfirm'];
    case PackageManager.unknown:
      return const [];
  }
}

/// ERE for one package name, as written in a sudoers rule.
String _packageNameRegex(PackageManager pkg) {
  return switch (pkg) {
    PackageManager.dnf ||
    PackageManager.yum ||
    PackageManager.zypper =>
      _packageName(notEnding: '.rpm'),
    // `name-` removes a package. `name:arch` is how apt lists foreign arches.
    PackageManager.apt =>
      '${_packageName(notEnding: '.deb', neverLast: '-')}(\\:[a-z0-9]+)?',
    PackageManager.apk => _packageName(notEnding: '.apk'),
    PackageManager.pacman => _packageName(),
    PackageManager.unknown => '',
  };
}

/// Whether [name] is one package name the rules would accept. The name comes
/// from the host's output, so nothing else may reach a sudoers line.
bool isSudoersSafePackageName(PackageManager pkg, String name) {
  final regex = _packageNameRegex(pkg).replaceAll(r'\:', ':');
  return regex.isNotEmpty && RegExp('^$regex\$').hasMatch(name);
}

List<String> _packageRegexCommands(PackageManager pkg) {
  final name = _packageNameRegex(pkg);
  return switch (pkg) {
    PackageManager.dnf => ['/usr/bin/dnf ^upgrade -y $name\$'],
    PackageManager.yum => ['/usr/bin/yum ^update -y $name\$'],
    PackageManager.apt => [
        r'/usr/bin/apt-get ^-y -o Dpkg\:\:Options\:\:=--force-confold '
            'install --only-upgrade $name\$',
      ],
    PackageManager.zypper => [
        '/usr/bin/zypper ^--non-interactive update $name\$',
      ],
    PackageManager.apk => ['/sbin/apk ^add -u $name\$'],
    PackageManager.pacman => ['/usr/bin/pacman ^-S --noconfirm $name\$'],
    PackageManager.unknown => const [],
  };
}

List<String> _firewallCommands(FirewallBackend fw) {
  switch (fw) {
    case FirewallBackend.firewalld:
      return const [
        '/usr/bin/firewall-cmd --get-default-zone',
        '/usr/bin/firewall-cmd --list-all',
        '/usr/bin/firewall-cmd --reload',
      ];
    case FirewallBackend.ufw:
      return const ['/usr/sbin/ufw status verbose'];
    case FirewallBackend.nftables:
      return const [
        '/usr/sbin/nft -j list ruleset',
        '/usr/sbin/nft -a list chain inet filter input',
        '/usr/sbin/nft -j list chain inet filter input',
      ];
    case FirewallBackend.iptables:
      return const ['/usr/sbin/iptables-save ""'];
    case FirewallBackend.none:
      return const [];
  }
}

const _firewalldZone = '(--zone=[a-zA-Z0-9_-]+ )?';
const _firewalldPort = '[0-9]+(-[0-9]+)?/(tcp|udp|sctp|dccp)';

List<String> _firewallRegexCommands(FirewallBackend fw) {
  switch (fw) {
    case FirewallBackend.firewalld:
      return const [
        '/usr/bin/firewall-cmd ^$_firewalldZone--add-port=$_firewalldPort'
            '( --timeout=60)?\$',
        '/usr/bin/firewall-cmd ^$_firewalldZone--remove-port=$_firewalldPort\$',
        '/usr/bin/firewall-cmd ^$_firewalldZone'
            '--permanent --(add|remove)-port=$_firewalldPort\$',
      ];
    case FirewallBackend.ufw:
      return const [
        r'/usr/sbin/ufw ^(delete )?allow [0-9]+(/(tcp|udp))?$',
      ];
    case FirewallBackend.nftables:
      return const [
        '/usr/sbin/nft ^add rule inet filter input (tcp|udp) dport [0-9]+ '
            r'accept comment kelola$',
        r'/usr/sbin/nft ^delete rule inet filter input handle [0-9]+$',
      ];
    case FirewallBackend.iptables:
    case FirewallBackend.none:
      return const [];
  }
}

/// One unit, for lifecycle verbs only. `enable`, `disable`, `link` and `edit`
/// are left out on purpose: they take a unit file path, so allowing them
/// passwordless would let this login run anything as root. The first character
/// rules out options such as `--host` and `--root`, and the class rules out a
/// path. `\:` in the class also admits a backslash, which is how systemd
/// escapes unit names such as `foo\x2dbar.service`.
List<String> _serviceRegexCommands(InitSystem init) {
  if (init != InitSystem.systemd) {
    return const [];
  }
  return const [
    '/usr/bin/systemctl ^(start|stop|restart|reload) $_unitNameRegex\$',
  ];
}

const _unitNameRegex = r'[a-zA-Z0-9][a-zA-Z0-9\:_.@-]*';

/// Whether [name] is one unit name the service rule would accept. The name
/// comes from the host's output, so nothing else may reach a sudoers line.
bool isSudoersSafeUnitName(String name) {
  final regex = _unitNameRegex.replaceAll(r'\:', r'\\:');
  return RegExp('^$regex\$').hasMatch(name);
}

/// The two signals the Processes screen sends, to one PID that is not 1. The
/// app's sshd guard still does not apply to direct sudo use: this login can
/// signal any other process, including sshd.
///
/// At most 7 digits, because Linux caps PIDs at 4194304. procps and util-linux
/// `kill` truncate to 32 bits, so with no cap 4294967297 reaches PID 1 and
/// 4294967295 reaches every process. Written without `{2,7}`, since a comma
/// ends a sudoers command.
const _processRegexCommands = [
  r'/usr/bin/kill ^-s (TERM|KILL) '
      r'([2-9]|[1-9][0-9][0-9]?[0-9]?[0-9]?[0-9]?[0-9]?)$',
];
