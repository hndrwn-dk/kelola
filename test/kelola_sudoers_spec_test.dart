import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/k8s/custom_columns.dart';
import 'package:kelola/domain/k8s/kubectl.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/cluster_health_probe.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/coreos_node_probe.dart';
import 'package:kelola/domain/probes/firewall_apply_probe.dart';
import 'package:kelola/domain/probes/firewall_list_probe.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/probes/workload_exec_probe.dart';
import 'package:kelola/domain/probes/workload_logs_probe.dart';
import 'package:kelola/domain/probes/workload_probes.dart';
import 'package:kelola/domain/probes/workload_yaml_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/units/service_unit.dart';

HostFacts facts({
  PackageManager pkg = PackageManager.dnf,
  FirewallBackend fw = FirewallBackend.firewalld,
  InitSystem init = InitSystem.systemd,
}) {
  return HostFacts(
    osId: 'rocky',
    osVersionId: '9',
    init: init,
    systemdVersion: 252,
    pkg: pkg,
    fw: fw,
    hasJournald: true,
    journalReadable: true,
    arch: 'x86_64',
  );
}

const regexSudo = ClassicSudo(1, 9, 15);
const oldestRegexSudo = ClassicSudo(1, 9, 10);

const noRegexFlavors = <String, SudoFlavor>{
  'classic 1.9.9': ClassicSudo(1, 9, 9),
  'classic 1.9.5': ClassicSudo(1, 9, 5),
  'classic 1.8.23': ClassicSudo(1, 8, 23),
  'sudo-rs': SudoRs('0.2.13'),
  'unknown': UnknownSudo(),
};

const allFlavors = <String, SudoFlavor>{
  'classic 1.9.15': regexSudo,
  'classic 1.9.10': oldestRegexSudo,
  ...noRegexFlavors,
};

KelolaSudoersSpec fullSpec(HostFacts f, SudoFlavor sudo) =>
    buildKelolaSudoersSpec(
      user: 'hendr',
      facts: f,
      groups: defaultKelolaSudoersGroups(f, sudo: sudo),
      sudo: sudo,
    );

/// Sudo's decision for [command]. With positive rules only, any match allows:
/// no args in a rule means any args, `""` means none, `^…$` is a regex, and
/// anything else is the exact argument string.
bool sudoAllows(KelolaSudoersSpec spec, String command) {
  final space = command.indexOf(' ');
  final path = space < 0 ? command : command.substring(0, space);
  final args = space < 0 ? '' : command.substring(space + 1);
  for (final rule in spec.commands) {
    expect(rule, isNot(startsWith('!')));
    final split = rule.indexOf(' ');
    final rulePath = split < 0 ? rule : rule.substring(0, split);
    if (rulePath != path) {
      continue;
    }
    if (split < 0) {
      return true;
    }
    // Sudo hands `\:` and `\,` to the regex as written; both match the
    // plain character.
    final ruleArgs = rule
        .substring(split + 1)
        .replaceAll(r'\:', ':')
        .replaceAll(r'\,', ',');
    final allowed = switch (ruleArgs) {
      '""' => args.isEmpty,
      // Sudo 1.9.15 never matches a regex argument over 1024 characters.
      final r when r.startsWith('^') =>
        r.length <= 1024 && RegExp(r).hasMatch(args),
      final r => r == args,
    };
    if (allowed) {
      return true;
    }
  }
  return false;
}

/// Each `sudo -n` argv in a probe script, as the host's shell would pass it.
List<String> sudoCommandsIn(String script) {
  final unquoted = script
      .replaceAll(r"'\''", '')
      .replaceAll("'", '')
      .replaceAll(r'$h', '7');
  return [
    for (final m in RegExp(r'sudo -n ([^\n;|<>&]+)').allMatches(unquoted))
      m.group(1)!.trim(),
  ];
}

/// `sudo -n kill` finds the binary through secure_path; rules name the path.
String withPath(String command) {
  for (final name in const ['systemctl', 'kill']) {
    if (command.startsWith('$name ')) {
      return '/usr/bin/$command';
    }
  }
  return command;
}

const packageManagers = [
  PackageManager.dnf,
  PackageManager.yum,
  PackageManager.apt,
  PackageManager.zypper,
  PackageManager.apk,
  PackageManager.pacman,
];

const writableBackends = [
  FirewallBackend.firewalld,
  FirewallBackend.ufw,
  FirewallBackend.nftables,
];

List<String> singlePackageCommands(PackageManager pkg) => [
      for (final name in [
        'openssl',
        'python3.11',
        'kernel-core',
        'glibc-langpack-en',
        'gcc-c++',
        'libstdc++',
        'rpm',
        'librpm',
        'deb',
        'apk',
        'r',
        if (pkg == PackageManager.apt) 'libc6:i386',
      ])
        ...sudoCommandsIn(
          PackageCommands.apply(pkg, securityOnly: false, names: [name]),
        ),
    ];

List<String> fixedPackageCommands(PackageManager pkg) => [
      ...sudoCommandsIn(PackageCommands.listUpdates(pkg)),
      ...sudoCommandsIn(PackageCommands.listSecurity(pkg)),
      ...sudoCommandsIn(PackageCommands.apply(pkg, securityOnly: true)),
      ...sudoCommandsIn(PackageCommands.apply(pkg, securityOnly: false)),
    ];

List<String> firewallChangeCommands(HostFacts f) {
  final scripts = <String>[];
  for (final verb in FirewallVerb.values) {
    for (final zone in const [null, 'public', 'my_zone-1']) {
      for (final port in const ['8080/tcp', '53/udp']) {
        final change = FirewallChange(
          verb: verb,
          port: port,
          zone: zone,
          handle: '42',
          revertPid: 99,
        );
        scripts
          ..add(FirewallApplyProbe(change).command(f))
          ..add(FirewallRevertProbe(change).command(f))
          ..add(FirewallKeepProbe(change).command(f));
      }
    }
  }
  return [...scripts.expand(sudoCommandsIn)];
}

List<String> serviceCommands() {
  final f = facts();
  return [
    for (final verb in const [
      UnitVerb.start,
      UnitVerb.stop,
      UnitVerb.restart,
      UnitVerb.reload,
    ])
      for (final unit in const [
        'nginx.service',
        'getty@tty1.service',
        'dbus-:1.2-org.a@0.service',
        'nginx',
      ])
        ...sudoCommandsIn(
          UnitActionProbe(unitName: unit, verb: verb).command(f),
        ).map(withPath),
  ];
}

List<String> processCommands() {
  final f = facts();
  return [
    for (final signal in ProcessSignal.values)
      for (final pid in const [2, 9, 10, 4242, 4194304])
        ...sudoCommandsIn(
          ProcessSignalProbe(
            pid: pid,
            signal: signal,
            commandName: 'worker',
          ).command(f),
        ).map(withPath),
  ];
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
      sudo: regexSudo,
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
    expect(spec.commands, contains('/usr/bin/dnf upgrade -y'));
    expect(spec.commands, contains('/usr/bin/dnf upgrade -y --security'));
    expect(spec.content, contains('/usr/bin/firewall-cmd --list-all'));
    expect(spec.content, contains('/usr/sbin/reboot ""'));
    expect(spec.content, contains('/usr/sbin/poweroff ""'));
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
      sudo: regexSudo,
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
      sudo: regexSudo,
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
      sudo: regexSudo,
    );
    expect(spec.content.trim(), startsWith('#'));
    expect(spec.commands, isEmpty);
  });

  group('default groups', () {
    test('are the full available set where regex works', () {
      expect(
        defaultKelolaSudoersGroups(facts(), sudo: regexSudo),
        {
          KelolaSudoersGroup.packages,
          KelolaSudoersGroup.firewall,
          KelolaSudoersGroup.hostPower,
          KelolaSudoersGroup.caches,
          KelolaSudoersGroup.services,
          KelolaSudoersGroup.processes,
        },
      );
    });

    test('omit packages and firewall when facts lack them', () {
      final groups = defaultKelolaSudoersGroups(
        facts(pkg: PackageManager.unknown, fw: FirewallBackend.none),
        sudo: regexSudo,
      );
      expect(groups, isNot(contains(KelolaSudoersGroup.packages)));
      expect(groups, isNot(contains(KelolaSudoersGroup.firewall)));
    });

    noRegexFlavors.forEach((name, sudo) {
      test('name no empty group on $name', () {
        expect(
          defaultKelolaSudoersGroups(facts(), sudo: sudo),
          {
            KelolaSudoersGroup.packages,
            KelolaSudoersGroup.firewall,
            KelolaSudoersGroup.hostPower,
            KelolaSudoersGroup.caches,
          },
        );
      });
    });

    test('only systemd hosts get service rules', () {
      final openrc = HostFacts.undiscovered.copyWith(init: InitSystem.openrc);
      expect(
        defaultKelolaSudoersGroups(openrc, sudo: regexSudo),
        isNot(contains(KelolaSudoersGroup.services)),
      );
      expect(
        buildKelolaSudoersSpec(
          user: 'u',
          facts: openrc,
          groups: const {KelolaSudoersGroup.services},
          sudo: regexSudo,
        ).commands,
        isEmpty,
      );
    });
  });

  group('every generated file', () {
    allFlavors.forEach((name, sudo) {
      test('is positive rules with no wildcard on $name', () {
        for (final pkg in packageManagers) {
          for (final fw in FirewallBackend.values) {
            final spec = fullSpec(facts(pkg: pkg, fw: fw), sudo);
            expect(spec.content, contains('# Positive rules only.'));
            expect(spec.content, isNot(contains('NOPASSWD: !')));
            expect(spec.content, isNot(contains('NOPASSWD: ALL')));
            for (final rule in spec.commands) {
              expect(rule, contains(' '), reason: 'bare binary: $rule');
              final args = rule.substring(rule.indexOf(' ') + 1);
              if (args.startsWith('^')) {
                expect(args, endsWith(r'$'), reason: rule);
                expect(sudo.supportsArgRegex, isTrue, reason: rule);
              } else {
                expect(args, isNot(contains('*')), reason: rule);
                expect(args, isNot(contains('[')), reason: rule);
              }
            }
          }
        }
      });
    });

    test('service and process rules never name an unsafe verb', () {
      final spec = fullSpec(facts(), regexSudo);
      for (final bad in ['enable', 'disable', 'link', 'edit', 'mask']) {
        expect(spec.content, isNot(contains(bad)), reason: bad);
      }
    });
  });

  group('commands Kelola runs', () {
    allFlavors.forEach((name, sudo) {
      test('with fixed arguments are allowed on $name', () {
        for (final pkg in packageManagers) {
          final spec = fullSpec(facts(pkg: pkg), sudo);
          final commands = fixedPackageCommands(pkg);
          expect(commands, isNotEmpty);
          for (final cmd in commands) {
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
        }
        for (final fw in FirewallBackend.values) {
          final f = facts(fw: fw);
          final spec = fullSpec(f, sudo);
          for (final cmd in sudoCommandsIn(
            const FirewallListProbe().command(f),
          )) {
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
          for (final verb in const [HostVerb.reboot, HostVerb.poweroff]) {
            for (final cmd in sudoCommandsIn(HostActionProbe(verb).command(f))) {
              expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
            }
          }
        }
        expect(
          sudoAllows(
            fullSpec(facts(), sudo),
            '/usr/bin/firewall-cmd --reload',
          ),
          isTrue,
        );
      });
    });

    for (final sudo in const [regexSudo, oldestRegexSudo]) {
      final label = '${sudo.major}.${sudo.minor}.${sudo.patch}';

      test('with a variable value are allowed on classic $label', () {
        for (final pkg in packageManagers) {
          final spec = fullSpec(facts(pkg: pkg), sudo);
          for (final cmd in singlePackageCommands(pkg)) {
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
        }
        for (final fw in writableBackends) {
          final f = facts(fw: fw);
          final spec = fullSpec(f, sudo);
          final commands = firewallChangeCommands(f);
          expect(commands, isNotEmpty);
          for (final cmd in commands) {
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
        }
        final spec = fullSpec(facts(), sudo);
        for (final cmd in [...serviceCommands(), ...processCommands()]) {
          expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
        }
      });
    }

    noRegexFlavors.forEach((name, sudo) {
      test('with a variable value are not granted on $name', () {
        for (final pkg in packageManagers) {
          final spec = fullSpec(facts(pkg: pkg), sudo);
          for (final cmd in singlePackageCommands(pkg)) {
            expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
          }
        }
        for (final fw in writableBackends) {
          final f = facts(fw: fw);
          final spec = fullSpec(f, sudo);
          final fixed = sudoCommandsIn(const FirewallListProbe().command(f));
          for (final cmd in firewallChangeCommands(f)) {
            if (fixed.contains(cmd) ||
                cmd.endsWith(' --reload') ||
                cmd.contains(' list chain ')) {
              continue;
            }
            expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
          }
        }
        final spec = fullSpec(facts(), sudo);
        for (final cmd in [...serviceCommands(), ...processCommands()]) {
          expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
        }
      });
    });
  });

  group('root and extra-argument forms are refused', () {
    void expectRefused(HostFacts f, List<String> commands) {
      allFlavors.forEach((name, sudo) {
        final spec = fullSpec(f, sudo);
        for (final cmd in commands) {
          expect(sudoAllows(spec, cmd), isFalse, reason: '$name: $cmd');
        }
      });
    }

    test('dnf and yum', () {
      for (final (pkg, base) in const [
        (PackageManager.dnf, '/usr/bin/dnf upgrade -y'),
        (PackageManager.yum, '/usr/bin/yum update -y'),
      ]) {
        expectRefused(facts(pkg: pkg), [
          '$base -c /tmp/evil.conf x',
          '$base -c/tmp/evil.conf',
          '$base --setopt=pluginpath=/tmp/p x',
          '$base --installroot=/tmp/x foo',
          '$base --nogpgcheck',
          '$base foo --nogpgcheck',
          '$base foo bar',
          '$base foo\tbar',
          '$base foo\n--nogpgcheck',
          '$base evil.rpm',
          '$base a.rpm',
          '$base .rpm',
          '$base ./evil.rpm',
          '$base /tmp/evil.rpm',
          '$base file:evil',
          '$base http://x/evil.rpm',
          '$base @group',
          '$base foo=1',
        ]);
      }
    });

    test('apt', () {
      const base = '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold';
      expectRefused(facts(pkg: PackageManager.apt), [
        '$base install --only-upgrade -o Dpkg::Pre-Invoke::=/tmp/x foo',
        '$base install --only-upgrade -o APT::Get::Only-Upgrade=false foo',
        '$base install --only-upgrade ./evil.deb',
        '$base install --only-upgrade evil.deb',
        '$base install --only-upgrade evil.deb:amd64',
        '$base install --only-upgrade .',
        '$base install --only-upgrade sudo-',
        '$base install --only-upgrade sudo-:amd64',
        '$base install --only-upgrade sudo:amd64-',
        '$base install --only-upgrade foo bar',
        '$base install --only-upgrade foo=1.0',
        '$base install --only-upgrade foo/stable',
        '$base install --only-upgrade a:b:c',
        '$base upgrade -o Dpkg::Pre-Invoke::=/tmp/x',
        '/usr/bin/apt-get -y install foo',
      ]);
    });

    test('zypper', () {
      const base = '/usr/bin/zypper --non-interactive update';
      expectRefused(facts(pkg: PackageManager.zypper), [
        '$base --repo dir:/tmp/r foo',
        '$base foo bar',
        '$base ./evil.rpm',
        '$base evil.rpm',
        '$base patch:foo',
      ]);
    });

    test('apk', () {
      expectRefused(facts(pkg: PackageManager.apk), [
        '/sbin/apk add -u --allow-untrusted /tmp/evil.apk',
        '/sbin/apk add -u --allow-untrusted evil.apk',
        '/sbin/apk add -u evil.apk',
        '/sbin/apk add -u --repository /tmp/r foo',
        '/sbin/apk add -u --root /tmp/r foo',
        '/sbin/apk add -u foo bar',
        '/sbin/apk add -u !sudo',
        '/sbin/apk add -u foo=1.0',
        '/sbin/apk upgrade --allow-untrusted',
      ]);
    });

    test('pacman', () {
      const base = '/usr/bin/pacman -S --noconfirm';
      expectRefused(facts(pkg: PackageManager.pacman), [
        '$base --hookdir /tmp/h foo',
        '$base --config /tmp/c foo',
        '$base --root /tmp/r foo',
        '$base foo bar',
        '$base core/foo',
        '/usr/bin/pacman -Syu --noconfirm --hookdir /tmp/h',
      ]);
    });

    test('firewall-cmd', () {
      const bin = '/usr/bin/firewall-cmd';
      expectRefused(facts(), [
        bin,
        '$bin --direct --passthrough ipv4 --modprobe=/tmp/x -t foo',
        '$bin --panic-on',
        '$bin --set-default-zone=trusted',
        '$bin --add-rich-rule=x',
        '$bin --add-port=1/tcp --direct --passthrough ipv4 -L',
        '$bin --add-port=1/tcp --zone=x --timeout=60',
        '$bin --add-port=1/tcp --timeout=999',
        '$bin --add-port=1/tcp --permanent',
        '$bin --zone=public --add-port=1/tcp --add-masquerade',
        '$bin --zone=public --zone=x --add-port=1/tcp',
        '$bin --zone=public --permanent --add-port=1/tcp --direct',
        '$bin --permanent --add-port=1/tcp --new-zone-from-file=/etc/shadow',
        '$bin --zone=public --permanent x --add-port=1/tcp',
        '$bin --zone=a/b --add-port=1/tcp',
        '$bin --add-port=a=b',
        '$bin --add-port=1',
        '$bin --add-port=1/foo',
        '$bin --list-all --x',
      ]);
    });

    test('ufw', () {
      const bin = '/usr/sbin/ufw';
      expectRefused(facts(fw: FirewallBackend.ufw), [
        bin,
        '$bin disable',
        '$bin --force reset',
        '$bin --rootdir=/tmp/x enable',
        '$bin allow --rootdir=/tmp/x 80',
        '$bin allow 80 --rootdir=/tmp/x',
        '$bin allow from 1.2.3.4',
        '$bin allow ssh',
        '$bin delete allow 1 extra',
        '$bin delete 1',
        '$bin status verbose --x',
      ]);
    });

    test('nft', () {
      const bin = '/usr/sbin/nft';
      const add = '$bin add rule inet filter input tcp dport';
      expectRefused(facts(fw: FirewallBackend.nftables), [
        bin,
        '$bin -f /etc/shadow',
        '$bin flush ruleset',
        '$bin -i',
        '$add 1 ; flush ruleset ; add rule x 2 accept comment kelola',
        '$add 1 drop accept comment kelola',
        '$add 1 accept comment kelola extra',
        '$bin delete rule inet filter input handle 1 x',
        '$bin delete rule inet filter input handle -f',
      ]);
    });

    test('iptables-save and host power take no arguments', () {
      expectRefused(facts(fw: FirewallBackend.iptables), [
        '/usr/sbin/iptables-save -f /etc/passwd',
        '/usr/sbin/iptables-save -M /tmp/x -t foo',
        '/usr/sbin/reboot -f',
        '/usr/sbin/poweroff --force',
      ]);
    });

    test('systemctl', () {
      const bin = '/usr/bin/systemctl';
      expectRefused(facts(), [
        bin,
        '$bin enable foo',
        '$bin disable foo',
        '$bin link /tmp/evil.service',
        '$bin edit foo',
        '$bin mask foo',
        '$bin start --host x foo',
        '$bin start -H x foo',
        '$bin start --root=/tmp foo',
        '$bin start foo --root=/tmp',
        '$bin start /tmp/evil.service',
        '$bin start ../evil.service',
        '$bin start foo bar',
        '$bin start -- foo',
      ]);
    });

    test('kill', () {
      const bin = '/usr/bin/kill';
      expectRefused(facts(), [
        bin,
        '$bin -s TERM 1',
        '$bin -s KILL 1',
        '$bin -s KILL 0',
        '$bin -s KILL 01',
        '$bin -s KILL -1',
        '$bin -s KILL 2 1',
        '$bin -s HUP 2',
        '$bin -9 2',
        '$bin -s KILL 2 3',
        // Real procps and util-linux kill truncate these to 1 and to -1.
        '$bin -s KILL 4294967297',
        '$bin -s KILL 4294967295',
        '$bin -s KILL 18446744073709551615',
        '$bin -s KILL 10000000',
      ]);
    });
  });

  group('sudo -n -l comparison', () {
    final spec = fullSpec(facts(), regexSudo);

    test('the same rules are current, as either sudo prints them', () {
      final classic = spec.commands
          .map((c) => c.replaceAll(r'\:', ':').replaceAll(':', r'\:'))
          .map((c) => c.replaceAll('=', r'\='))
          .toList();
      expect(kelolaSudoRulesOutdated(listed: classic, spec: spec), isFalse);
      final rs = spec.commands.map(normalizeSudoRule).toList();
      expect(kelolaSudoRulesOutdated(listed: rs, spec: spec), isFalse);
    });

    test('real listing from classic sudo before 1.9.10 is current', () {
      final plain = fullSpec(facts(), const ClassicSudo(1, 9, 9));
      final listed = plain.commands
          .map((c) => c.replaceAll('=', r'\=').replaceAll('""', r'\"\"'))
          .toList();
      expect(listed, contains(r'/usr/sbin/reboot \"\"'));
      expect(kelolaSudoRulesOutdated(listed: listed, spec: plain), isFalse);
    });

    test('parses the listing of each sudo', () {
      const classic = '''
Matching Defaults entries for u on h:
    env_reset, secure_path=/usr/bin

User u may run the following commands on h:
    (root) NOPASSWD: /usr/sbin/reboot ""
    (root) NOPASSWD: /usr/bin/dnf --color\\=never check
    (ALL : ALL) ALL
''';
      expect(parseSudoListing(classic), [
        '/usr/sbin/reboot ""',
        r'/usr/bin/dnf --color\=never check',
      ]);
    });

    test('a rule that was never installed is not outdated', () {
      expect(kelolaSudoRulesOutdated(listed: const [], spec: spec), isFalse);
      expect(
        kelolaSudoRulesOutdated(
          listed: const ['/usr/local/bin/backup'],
          spec: spec,
        ),
        isFalse,
      );
    });

    test('the old wide rules are outdated', () {
      for (final old in [
        '/usr/bin/firewall-cmd',
        '/usr/sbin/reboot',
        '/usr/bin/dnf upgrade -y *',
        '/usr/bin/systemctl start [a-zA-Z0-9]*',
        '!/usr/bin/dnf upgrade -y -*',
      ]) {
        expect(
          kelolaSudoRulesOutdated(
            listed: [...spec.commands, old],
            spec: spec,
          ),
          isTrue,
          reason: old,
        );
      }
    });

    test('a missing rule is outdated', () {
      expect(
        kelolaSudoRulesOutdated(
          listed: spec.commands.skip(1).toList(),
          spec: spec,
        ),
        isTrue,
      );
    });

    test('an exact rule a sudo hint suggested is not outdated', () {
      expect(
        kelolaSudoRulesOutdated(
          listed: [
            ...spec.commands,
            '/usr/bin/systemctl restart nginx.service',
          ],
          spec: spec,
        ),
        isFalse,
      );
    });
  });

  group('M52d one tap', () {
    test('Flush caches is one exact sysctl line on every sudo', () {
      for (final sudo in allFlavors.values) {
        final spec = fullSpec(facts(), sudo);
        expect(spec.groups, contains(KelolaSudoersGroup.caches));
        expect(spec.commands, contains(kelolaDropCachesCommand));
        expect(
          spec.commands.where((c) => c.startsWith('/usr/sbin/sysctl')),
          [kelolaDropCachesCommand],
        );
      }
      final probe =
          const HostActionProbe(HostVerb.dropCaches).command(facts());
      expect(probe, isNot(contains('sh -c')));
      expect(probe, startsWith('sync && '));
      final spec = fullSpec(facts(), regexSudo);
      for (final cmd in sudoCommandsIn(probe)) {
        expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
      }
      // Other sysctl writes are not allowed.
      for (final cmd in [
        '/usr/sbin/sysctl -w vm.drop_caches=1',
        '/usr/sbin/sysctl -w kernel.modprobe=/tmp/x',
        '/usr/sbin/sysctl -p /tmp/evil.conf',
        '/usr/sbin/sysctl',
      ]) {
        expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
      }
    });

    test('journald hosts get no log rule; syslog hosts get exact reads', () {
      final journald = fullSpec(facts(), regexSudo);
      expect(journald.groups, isNot(contains(KelolaSudoersGroup.logs)));
      expect(
        journald.commands.where(
          (c) => c.contains('journalctl') || c.startsWith('/usr/bin/tail'),
        ),
        isEmpty,
      );

      final syslogFacts = facts().copyWith(hasJournald: false);
      for (final sudo in allFlavors.values) {
        final spec = fullSpec(syslogFacts, sudo);
        expect(spec.groups, contains(KelolaSudoersGroup.logs));
        for (final path in ['/var/log/syslog', '/var/log/messages']) {
          for (final cmd in [
            '/usr/bin/test -r $path',
            '/usr/bin/tail -n 20 $path',
            '/usr/bin/tail -n 50 $path',
            '/usr/bin/tail -n 200 $path',
            '/usr/bin/tail -n 0 -F $path',
          ]) {
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
        }
        for (final cmd in [
          '/usr/bin/tail -n 20 /etc/shadow',
          '/usr/bin/tail -n 20 /var/log/syslog /etc/shadow',
          '/usr/bin/tail -F /var/log/syslog',
          '/usr/bin/test -r /etc/shadow',
          '/usr/bin/tail',
        ]) {
          expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
        }
        // Every rule is exact: no regex, no bare binary.
        for (final rule in spec.commands.where(
          (c) => c.startsWith('/usr/bin/tail') || c.startsWith('/usr/bin/test'),
        )) {
          expect(rule, isNot(contains('^')));
          expect(rule, contains(' '));
        }
      }
    });

    test('the journal screens read only the counts the tail lines allow', () {
      expect(kelolaSyslogTailLimits, containsAll([20, 50, 200]));
      final source = [
        'lib/presentation/widgets/diagnostic_pack_sheet.dart',
        'lib/presentation/widgets/incident_sheet.dart',
        'lib/presentation/screens/journal_screen.dart',
      ].map((p) => File(p).readAsStringSync()).join('\n');
      for (final m in RegExp(r'JournalProbe\([^)]*limit: (\d+)')
          .allMatches(source)) {
        expect(
          kelolaSyslogTailLimits,
          contains(int.parse(m.group(1)!)),
          reason: m.group(0),
        );
      }
    });

    test('a host without regex gets exact lines for the named units only', () {
      for (final sudo in noRegexFlavors.values) {
        final spec = buildKelolaSudoersSpec(
          user: 'hendr',
          facts: facts(),
          groups: defaultKelolaSudoersGroups(
            facts(),
            sudo: sudo,
            units: const ['nginx.service', 'getty@tty1.service'],
          ),
          sudo: sudo,
          units: const ['nginx.service', 'getty@tty1.service'],
        );
        expect(spec.groups, contains(KelolaSudoersGroup.services));
        for (final unit in ['nginx.service', 'getty@tty1.service']) {
          for (final verb in kelolaUnitLifecycleVerbs) {
            final cmd = '/usr/bin/systemctl $verb $unit';
            expect(spec.commands, contains(cmd));
            expect(sudoAllows(spec, cmd), isTrue, reason: cmd);
          }
        }
        for (final cmd in [
          '/usr/bin/systemctl restart sshd.service',
          '/usr/bin/systemctl enable nginx.service',
          '/usr/bin/systemctl link nginx.service',
          '/usr/bin/systemctl restart nginx.service sshd.service',
          '/usr/bin/systemctl',
        ]) {
          expect(sudoAllows(spec, cmd), isFalse, reason: cmd);
        }
      }
    });

    test('unit names from the host that are unsafe are dropped', () {
      final lines = exactUnitCommands(InitSystem.systemd, const [
        'nginx.service',
        'nginx.service',
        r'foo\x2dbar.service',
        '--root=/tmp',
        'a b.service',
        'x,y.service',
        'evil\n.service',
        '*',
        'dbus-org.freedesktop:1.service',
      ]);
      expect(lines, [
        for (final v in kelolaUnitLifecycleVerbs)
          '/usr/bin/systemctl $v nginx.service',
        for (final v in kelolaUnitLifecycleVerbs)
          r'/usr/bin/systemctl ' '$v' r' dbus-org.freedesktop\:1.service',
      ]);
      expect(exactUnitCommands(InitSystem.openrc, const ['nginx']), isEmpty);
    });

    test('a host with regex keeps the one pattern and no unit lines', () {
      final spec = buildKelolaSudoersSpec(
        user: 'hendr',
        facts: facts(),
        groups: defaultKelolaSudoersGroups(facts(), sudo: regexSudo),
        sudo: regexSudo,
        units: const ['nginx.service'],
      );
      expect(
        spec.commands.where((c) => c.startsWith('/usr/bin/systemctl')),
        hasLength(1),
      );
    });

    test('a host without regex and no units still has no Services group', () {
      for (final sudo in noRegexFlavors.values) {
        expect(
          defaultKelolaSudoersGroups(facts(), sudo: sudo),
          isNot(contains(KelolaSudoersGroup.services)),
        );
      }
    });

    test('installed Containers, Flush caches and Logs rules are current', () {
      final f = facts().copyWith(hasJournald: false, runtimes: ['docker']);
      for (final sudo in allFlavors.values) {
        final spec = fullSpec(f, sudo);
        expect(
          kelolaSudoRulesOutdated(listed: spec.commands, spec: spec),
          isFalse,
          reason: '$sudo',
        );
        for (final missing in [
          kelolaDropCachesCommand,
          '/usr/bin/docker info',
          '/usr/bin/tail -n 0 -F /var/log/syslog',
        ]) {
          expect(
            kelolaSudoRulesOutdated(
              listed: spec.commands.where((c) => c != missing).toList(),
              spec: spec,
            ),
            isTrue,
            reason: missing,
          );
        }
      }
    });
  });

  group('M52d Kubernetes reads', () {
    final k3s = facts().copyWith(runtimes: ['k3s', 'kubectl']);
    final kubectl = facts().copyWith(runtimes: ['kubectl']);
    final crictlNode = facts().copyWith(runtimes: ['crictl']);
    final oc = facts().copyWith(runtimes: ['oc', 'kubectl']);

    KelolaSudoersSpec k8sSpec(HostFacts f, [SudoFlavor sudo = regexSudo]) =>
        buildKelolaSudoersSpec(
          user: 'hendr',
          facts: f,
          groups: {KelolaSudoersGroup.kubernetes},
          sudo: sudo,
        );

    const workload = K8sWorkload(
      kind: K8sKind.deployment,
      namespace: 'kube-system',
      name: 'coredns',
      ready: 1,
      desired: 1,
    );

    /// The read argv each Kubernetes screen sends, after the binary.
    final reads = [
      'get --raw=/version',
      'get --raw=/readyz',
      'get --raw=/apis/config.openshift.io/v1',
      'config current-context',
      'get nodes --output=json',
      'get clusterversion version --output=json',
      'get csr --output=json',
      'get deploy,sts,ds,job,cronjob,pod --all-namespaces $kWorkloadSudoOutput',
      'get pods --all-namespaces $kPodSudoOutput',
      'get svc,endpoints --all-namespaces --output=json',
      'get pv,pvc --all-namespaces --output=json',
      'get sa,networkpolicy,clusterrolebinding --all-namespaces --output=json',
      'get events --all-namespaces --field-selector=type=Warning '
          '--output=json',
      '--namespace=default get events '
          '--field-selector=involvedObject.name=web-7c9d-x2k4p --output=json',
      '--namespace=default top pod --no-headers',
      '--namespace=default top pod web-7c9d-x2k4p --no-headers',
      '--namespace=default logs statefulset/db --tail=80 --timestamps',
      '--namespace=default logs cronjob/backup.nightly --tail=2000 '
          '--timestamps',
    ];

    /// Each one refused for k3s and kubectl alike, after the lead option.
    final refused = [
      // Anything that prints a pod template, and so its literal env values.
      '--namespace=kube-system describe deployment/coredns',
      '--namespace=default describe pod/web-7c9d-x2k4p',
      '--namespace=default get daemonset/fluent-bit --output=yaml',
      '--namespace=default get pod/web --output=yaml',
      'get deploy,sts,ds,job,cronjob,pod --all-namespaces --output=json',
      'get pods --all-namespaces --output=json',
      'get pods --all-namespaces --output=yaml',
      'get rs,controllerrevision --all-namespaces --output=json',
      'get rs,controllerrevision --namespace=shop --output=json',
      'get pods --all-namespaces '
          '--output=custom-columns=E:.spec.containers[*].env',
      'get pods --all-namespaces $kPodSudoOutput,E:.spec.containers[*].env',
      'get deploy,sts,ds,job,cronjob,pod --all-namespaces '
          '$kWorkloadSudoOutput,E:.spec.template.spec.containers[*].env',
      'get pods --all-namespaces $kWorkloadSudoOutput',
      'get deploy,sts,ds,job,cronjob,pod --all-namespaces $kPodSudoOutput',
      'get pods --all-namespaces ${kPodSudoOutput.replaceAll('.', 'x')}',
      // A kubeconfig can name an exec credential plugin, run as root.
      '--kubeconfig=/tmp/k get nodes --output=json',
      'get nodes --output=json --kubeconfig=/tmp/k',
      'get pods --all-namespaces --output=json --kubeconfig /tmp/k',
      // Templates and files read from disk.
      'get nodes --output=go-template-file=/tmp/t',
      'get nodes --output=jsonpath-file=/tmp/t',
      'get nodes --output=go-template={{.}}',
      'get nodes --output=jsonpath={.items}',
      'get nodes --output=json --template=/tmp/t',
      'get --filename=/tmp/x --output=json',
      'get -f /tmp/x --output=json',
      'get nodes --output=json --cache-dir=/tmp/c',
      // --raw beyond the fixed paths.
      'get --raw=/api/v1/secrets',
      'get --raw=/version/../api/v1/secrets',
      'get --raw=/versionx',
      'get --raw /version',
      // Logs to a file, other credentials and identities.
      'get nodes --output=json --log-file=/etc/cron.d/x',
      'get nodes --output=json --log-dir=/etc',
      'get nodes --output=json --profile=cpu --profile-output=/etc/x',
      '--server=https://evil:6443 get nodes --output=json',
      'get nodes --output=json --token=x',
      'get nodes --output=json --as=system:admin',
      'get nodes --output=json --as-group=system:masters',
      'get nodes --output=json --context=other',
      'get nodes --output=json --insecure-skip-tls-verify',
      // A jsonpath or name with a space cannot fake an extra option.
      '--namespace=default --kubeconfig=/tmp/k describe pod/web',
      '--namespace=default describe pod/web --kubeconfig=/tmp/k',
      '--namespace=default logs pod/web --kubeconfig=/k --tail=1 '
          '--timestamps',
      '--namespace=default get events --field-selector=involvedObject.name=a '
          '--kubeconfig=/k --output=json',
      '--namespace=default top pod web --kubeconfig=/k --no-headers',
      // Secrets and ConfigMaps never go through sudo.
      'get secrets --all-namespaces --output=json',
      'get secret --all-namespaces --output=json',
      'get pods,secrets --all-namespaces --output=json',
      '--namespace=default get secret/db --output=yaml',
      '--namespace=default describe secret/db',
      'get configmaps --all-namespaces --output=json',
      'config view --raw',
      'config view',
      'config use-context other',
      // Every mutating verb, and everything that runs code.
      '--namespace=default exec pod/web -- sh',
      '--namespace=default exec web -- id',
      '--namespace=default apply --filename=-',
      'apply -f /tmp/x',
      '--namespace=default diff --filename=-',
      '--namespace=default port-forward pod/web 8080:80',
      '--namespace=default delete pod/web',
      '--namespace=default scale deployment/web --replicas=0',
      '--namespace=default edit deployment/web',
      '--namespace=default patch deployment/web --patch={}',
      '--namespace=default rollout restart deployment/web',
      '--namespace=default rollout status deployment/web --timeout=120s',
      '--namespace=default run x --image=busybox',
      '--namespace=default debug pod/web',
      '--namespace=default cp pod/web:/etc/shadow /tmp/x',
      '--namespace=default attach pod/web',
      '--namespace=default label pod/web a=b',
      'drain node1',
      'cordon node1',
      'proxy',
      'certificate approve csr-1',
      'plugin list',
      'create token default',
      'auth can-i --list',
      // Short options, other shapes and odd values.
      '-n default describe pod/web',
      'get nodes -o json',
      'get pods -A --output=json',
      '--namespace=default logs pod/web --tail=80 --timestamps --follow',
      '--namespace=default logs pod/web --tail=-1 --timestamps',
      '--namespace=default logs pod/web --tail=80 --timestamps '
          '--all-containers',
      '--namespace=default logs pod/web --tail=80 --timestamps '
          '--previous=true',
      '--namespace=-x describe pod/web',
      '--namespace=Default describe pod/web',
      '--namespace=default describe pod/-web',
      '--namespace=default describe pod/web/x',
      '--namespace=default describe pod/web,secret/db',
      '--namespace=default describe pod/web secret/db',
      '--namespace=default describe deployment',
      '--namespace=default get events '
          '--field-selector=involvedObject.name=a,type=Normal --output=json',
      '--namespace=default get events '
          '--field-selector=involvedObject.name!=a --output=json',
      '--namespace=default get pod/web --output=json',
      '',
    ];

    test('default only with regex sudo and a k3s or kubectl CLI', () {
      for (final f in [k3s, kubectl, crictlNode]) {
        expect(
          defaultKelolaSudoersGroups(f, sudo: regexSudo),
          contains(KelolaSudoersGroup.kubernetes),
          reason: '${f.runtimes}',
        );
        noRegexFlavors.forEach((name, sudo) {
          expect(
            defaultKelolaSudoersGroups(f, sudo: sudo),
            isNot(contains(KelolaSudoersGroup.kubernetes)),
            reason: name,
          );
          // Even when asked for, no rule: today's behaviour.
          expect(k8sSpec(f, sudo).commands, isEmpty, reason: name);
        });
      }
      for (final f in [facts(), facts().copyWith(runtimes: ['oc'])]) {
        expect(
          defaultKelolaSudoersGroups(f, sudo: regexSudo),
          isNot(contains(KelolaSudoersGroup.kubernetes)),
          reason: '${f.runtimes}',
        );
      }
    });

    test('rules name the CLI that facts pick, never oc', () {
      expect(k8sSpec(k3s).commands, isNotEmpty);
      for (final c in k8sSpec(k3s).commands) {
        expect(c, startsWith('$kelolaK3sPath ^kubectl $kSudoKubectlLead ('));
      }
      expect(
        k8sSpec(kubectl).commands.map((c) => c.split(' ').first).toSet(),
        kelolaKubectlPaths.toSet(),
      );
      for (final c in k8sSpec(kubectl).commands) {
        expect(c.split(' ')[1], startsWith('^$kSudoKubectlLead'));
      }
      // Every path gets the same lines.
      final lines = k8sSpec(kubectl).commands.length;
      expect(lines % kelolaKubectlPaths.length, 0);
      expect(lines ~/ kelolaKubectlPaths.length, k8sSpec(k3s).commands.length);
      expect(k8sSpec(crictlNode).commands, [
        for (final p in kelolaCrictlPaths) '$p ps --output=json',
      ]);
      // oc wins over kubectl and may live under the login's home.
      expect(k8sSpec(oc).commands, isEmpty);
      for (final f in [k3s, kubectl, crictlNode, oc]) {
        final content = k8sSpec(f).content;
        expect(content, isNot(contains(' oc')));
        expect(content, isNot(contains('.crc')));
        expect(content, isNot(contains('*/')));
      }
    });

    test('reads are allowed for k3s kubectl and kubectl', () {
      for (final read in reads) {
        expect(
          sudoAllows(
            k8sSpec(k3s),
            '$kelolaK3sPath kubectl $kSudoKubectlLead $read',
          ),
          isTrue,
          reason: 'k3s: $read',
        );
        for (final path in kelolaKubectlPaths) {
          expect(
            sudoAllows(k8sSpec(kubectl), '$path $kSudoKubectlLead $read'),
            isTrue,
            reason: '$path: $read',
          );
        }
        // Without the lead option nothing matches.
        expect(
          sudoAllows(k8sSpec(k3s), '$kelolaK3sPath kubectl $read'),
          isFalse,
          reason: read,
        );
      }
    });

    test('kubeconfig, templates, raw paths, secrets and every mutate are '
        'refused', () {
      for (final bad in refused) {
        final args = bad.isEmpty ? kSudoKubectlLead : '$kSudoKubectlLead $bad';
        expect(
          sudoAllows(k8sSpec(k3s), '$kelolaK3sPath kubectl $args'),
          isFalse,
          reason: 'k3s: $bad',
        );
        for (final path in kelolaKubectlPaths) {
          expect(
            sudoAllows(k8sSpec(kubectl), '$path $args'),
            isFalse,
            reason: '$path: $bad',
          );
        }
      }
      // k3s itself: only its kubectl.
      for (final bad in [
        'server',
        'crictl ps',
        'ctr images ls',
        'kubectl',
        'etcd-snapshot save',
        '--data-dir=/tmp/x kubectl $kSudoKubectlLead get nodes --output=json',
        'kubectl --data-dir=/tmp/x $kSudoKubectlLead get nodes --output=json',
      ]) {
        expect(
          sudoAllows(k8sSpec(k3s), '$kelolaK3sPath $bad'),
          isFalse,
          reason: bad,
        );
      }
      for (final bad in [
        'ps',
        'ps -o json',
        'ps --output=json --config=/tmp/c',
        'exec -it abc sh',
        'inspect abc',
        'rm abc',
      ]) {
        for (final path in kelolaCrictlPaths) {
          expect(
            sudoAllows(k8sSpec(crictlNode), '$path $bad'),
            isFalse,
            reason: '$path $bad',
          );
        }
      }
    });

    test('a re-split argv never starts a short option or a command', () {
      // Sudo matches the arguments joined with spaces, so the login may
      // split or join them at any space. Every option is one `--` argument
      // and the first is an option: no piece starts with a single `-` (a
      // cluster of short options) and kubectl never reads a joined piece as
      // its command or a plugin name.
      for (final read in reads) {
        final tokens = '$kSudoKubectlLead $read'.split(' ');
        expect(tokens.first, startsWith('--'), reason: read);
        for (final t in tokens) {
          expect(t, isNot(matches(RegExp(r'^-[^-]'))), reason: read);
        }
      }
      for (final shape in kelolaK8sReadShapes) {
        expect(shape, isNot(matches(RegExp(r'(^| )-[^-]'))), reason: shape);
      }
    });

    test('no allowed read prints a pod template or its env values', () {
      // The same rule M52c applies to docker inspect: env values often hold
      // database or API credentials.
      for (final (_, path) in [...kWorkloadSudoColumns, ...kPodSudoColumns]) {
        for (final bad in [
          'env',
          'args',
          'command',
          'template',
          'annotations',
          'volumes',
          'data',
        ]) {
          final segments = path
              .split('.')
              .map((s) => s.replaceAll(RegExp(r'\[.*\]'), '').toLowerCase());
          expect(segments, isNot(contains(bad)), reason: path);
        }
        expect(path, isNot(contains(' ')), reason: path);
      }
      // The only spec field of a container is the first image.
      expect(
        [...kWorkloadSudoColumns, ...kPodSudoColumns]
            .map((c) => c.$2)
            .where((p) => p.contains('containers'))
            .where((p) => p.startsWith('.spec')),
        ['.spec.containers[0].image'],
      );
      final shapes = kelolaK8sReadShapes.join('\n');
      for (final bad in [
        'describe',
        'yaml',
        'controllerrevision',
        r'rs\,',
        'jsonpath',
        'go-template',
      ]) {
        expect(shapes, isNot(contains(bad)), reason: bad);
      }
      // `--output=json` only for kinds with no pod template.
      for (final shape in kelolaK8sReadShapes) {
        if (!shape.contains('--output=json')) continue;
        for (final kind in ['pod', 'deploy', 'sts', 'ds', 'job', 'cronjob']) {
          expect(
            shape.split(' ').take(2).join(' '),
            isNot(contains(RegExp('(^|[ (,|])$kind([ ,)|]|\$)'))),
            reason: shape,
          );
        }
      }
    });

    test('the Kubernetes binaries get a pinned environment', () {
      for (final f in [k3s, kubectl, crictlNode]) {
        final spec = fullSpec(f, regexSudo);
        expect(spec.defaults, kelolaK8sDefaults, reason: '${f.runtimes}');
        final lines = spec.content.split('\n');
        final alias = lines.indexWhere((l) => l.startsWith('Cmnd_Alias '));
        final defaults = lines.indexWhere((l) => l.startsWith('Defaults!'));
        final firstRule = lines.indexWhere((l) => l.contains(' NOPASSWD: '));
        expect(alias, greaterThan(0));
        expect(alias, lessThan(defaults));
        expect(defaults, lessThan(firstRule));
        expect(
          lines[alias],
          'Cmnd_Alias $kelolaK8sCmndAlias = '
          '${[kelolaK3sPath, ...kelolaKubectlPaths, ...kelolaCrictlPaths].join(', ')}',
        );
        expect(lines[defaults], startsWith('Defaults!$kelolaK8sCmndAlias '));
        for (final setting in [
          'env_reset',
          'always_set_home',
          '!setenv',
          'env_keep -= "HOME KUBECONFIG"',
        ]) {
          expect(lines[defaults], contains(setting));
        }
        // Every path a rule names is in the alias.
        for (final rule in kubernetesReadCommands(f)) {
          expect(lines[alias], contains(rule.split(' ').first));
        }
      }
      // No Kubernetes rule, no Defaults.
      for (final f in [facts(), oc]) {
        expect(fullSpec(f, regexSudo).defaults, isEmpty);
        expect(fullSpec(f, regexSudo).content, isNot(contains('Defaults')));
      }
      noRegexFlavors.forEach((name, sudo) {
        expect(fullSpec(k3s, sudo).content, isNot(contains('Defaults')),
            reason: name);
      });
    });

    test('sudo -l lists Defaults apart, and the comparison ignores them', () {
      final spec = fullSpec(k3s, regexSudo);
      final listing = [
        'Matching Defaults entries for hendr on node1:',
        '    env_reset, mail_badpass, secure_path=/usr/sbin\\:/usr/bin',
        '',
        'Runas and Command-specific defaults for hendr:',
        '    Defaults!$kelolaK8sCmndAlias env_reset, always_set_home, '
            '!setenv, env_keep-="HOME KUBECONFIG"',
        '',
        'User hendr may run the following commands on node1:',
        for (final c in spec.commands) '    (root) NOPASSWD: $c',
      ].join('\n');
      expect(parseSudoListing(listing), spec.commands);
      expect(
        kelolaSudoRulesOutdated(
          listed: parseSudoListing(listing),
          spec: spec,
        ),
        isFalse,
      );
    });

    test('no regex argument is long enough for sudo to stop matching it', () {
      // Sudo 1.9.15 silently never matches a regex argument past 1024
      // characters; visudo still accepts the file.
      for (final f in [k3s, kubectl, crictlNode, facts()]) {
        for (final sudo in [regexSudo, oldestRegexSudo]) {
          for (final rule in fullSpec(f, sudo).commands) {
            final args = rule.substring(rule.indexOf(' ') + 1);
            if (!args.startsWith('^')) continue;
            expect(
              args.length,
              lessThanOrEqualTo(kelolaSudoRegexArgMax),
              reason: rule,
            );
          }
        }
      }
    });

    test('rules round-trip through the sudo -n -l comparison', () {
      for (final f in [k3s, kubectl, crictlNode]) {
        final spec = fullSpec(f, regexSudo);
        // Sudo 1.9.15 lists them as written; a sudo that drops `\,` or adds
        // `\=` lists the same rules.
        for (final listed in [
          spec.commands,
          [for (final c in spec.commands) c.replaceAll(r'\,', ',')],
          [for (final c in spec.commands) c.replaceAll('=', r'\=')],
        ]) {
          expect(
            kelolaSudoRulesOutdated(listed: listed, spec: spec),
            isFalse,
            reason: '${f.runtimes}',
          );
        }
        // A file from before this group is outdated on a cluster host.
        final before = spec.commands
            .where((c) => !kubernetesReadCommands(f).contains(c))
            .toList();
        expect(
          kelolaSudoRulesOutdated(listed: before, spec: spec),
          isTrue,
          reason: '${f.runtimes}',
        );
      }
    });

    group('every sudo argv the probes send', () {
      /// `sudo -n` argv in [script] with each binary's sudoers path.
      List<String> sudoArgv(String script) => [
            for (final c in sudoCommandsIn(script))
              c.replaceFirst(RegExp(r' 2$'), ''),
          ];

      List<String> paths(String command) {
        final bin = command.split(' ').first;
        final rest = command.substring(bin.length);
        return switch (bin) {
          'k3s' => ['$kelolaK3sPath$rest'],
          'kubectl' => [for (final p in kelolaKubectlPaths) '$p$rest'],
          'crictl' => [for (final p in kelolaCrictlPaths) '$p$rest'],
          _ => [command],
        };
      }

      const pod = ContainerRow(
        id: 'default/web-7c9d-x2k4p',
        names: 'web-7c9d-x2k4p',
        namespace: 'default',
        image: 'nginx',
        state: 'running',
        status: 'Running',
        engine: 'k3s',
      );

      final readProbes = <Probe<Object?>>[
        const ClusterHealthProbe(),
        const FleetClusterProbe(),
        const ClusterEventsProbe(),
        const ServiceListProbe(),
        const StorageListProbe(),
        const SecurityInventoryProbe(),
        const WorkloadListProbe(),
        const FleetWorkloadListProbe(),
        const WorkloadEventsProbe(namespace: 'default', name: 'web-1'),
        const WorkloadTopProbe(namespace: 'default'),
        const WorkloadTopProbe(namespace: 'default', pod: 'web-1'),
        const WorkloadLogsProbe(workload),
        const WorkloadLogsProbe(workload, tail: 2000),
        const OpenShiftHealthProbe(),
        const FleetOpenShiftProbe(),
        const ContainerListProbe(),
        const CoreOsNodeProbe(),
      ];

      test('each read probe matches a rule', () {
        for (final f in [k3s, kubectl, crictlNode]) {
          final spec = k8sSpec(f);
          var checked = 0;
          for (final probe in readProbes) {
            for (final cmd in sudoArgv(probe.command(f))) {
              final bin = cmd.split(' ').first;
              final covered = switch (bin) {
                'k3s' => f == k3s,
                'kubectl' => f == kubectl,
                'crictl' => f.runtimes.contains('crictl'),
                _ => false,
              };
              if (!covered) {
                continue;
              }
              for (final full in paths(cmd)) {
                expect(
                  sudoAllows(spec, full),
                  isTrue,
                  reason: '${probe.runtimeType}: $full',
                );
                checked++;
              }
            }
          }
          expect(checked, greaterThan(0), reason: '${f.runtimes}');
        }
      });

      test('no mutate, exec, port-forward, Secret listing or pod template '
          'read matches', () {
        final mutating = <String>[
          for (final verb in WorkloadVerb.values)
            ...[k3s, kubectl].map(
              (f) => WorkloadActionProbe(
                workload: workload,
                verb: verb,
                replicas: 3,
              ).command(f),
            ),
          for (final f in [k3s, kubectl]) ...[
            const WorkloadExecProbe(workload: workload, line: 'id').command(f),
            const WorkloadYamlDiffProbe(workload: workload, yaml: 'a: 1')
                .command(f),
            const WorkloadYamlApplyProbe(workload: workload, yaml: 'a: 1')
                .command(f),
            const WorkloadRolloutStatusProbe(workload: workload).command(f),
            const ConfigInventoryProbe().command(f),
            // Reads whose output holds a pod template and its env values.
            for (final kind in K8sKind.values)
              WorkloadDescribeProbe(kind: kind, namespace: 'default', name: 'web')
                  .command(f),
            const WorkloadYamlGetProbe(workload: workload).command(f),
            const RolloutHistoryProbe().command(f),
            const RolloutHistoryProbe(namespace: 'shop').command(f),
            const ContainerActionProbe(row: pod, verb: ContainerVerb.inspect)
                .command(f),
            kubectlPortForwardCommand(f, resource: 'svc/web', port: 80),
          ],
        ];
        var checked = 0;
        for (final script in mutating) {
          for (final cmd in sudoArgv(script)) {
            for (final full in paths(cmd)) {
              // The connection check before the verb is the only read.
              if (full.endsWith('$kSudoKubectlLead get --raw=/version')) {
                continue;
              }
              for (final f in [k3s, kubectl]) {
                expect(
                  sudoAllows(k8sSpec(f), full),
                  isFalse,
                  reason: full,
                );
              }
              checked++;
            }
          }
        }
        expect(checked, greaterThan(10));
      });
    });
  });

  group('real visudo accepts every generated file', () {
    final ciRequired = Platform.environment['CI'] == 'true';

    /// The first of [paths] whose `--version` matches [isThisFlavor].
    String? find(List<String> paths, bool Function(String) isThisFlavor) {
      for (final path in paths) {
        if (!File(path).existsSync()) {
          continue;
        }
        final version = Process.runSync(path, ['--version']);
        if (isThisFlavor('${version.stdout}${version.stderr}')) {
          return path;
        }
      }
      return null;
    }

    void check(
      String label,
      String? visudo,
      Map<String, SudoFlavor> flavors,
    ) {
      test(label, () {
        if (visudo == null) {
          expect(ciRequired, isFalse, reason: 'CI must have $label');
          markTestSkipped('$label is not installed here');
          return;
        }
        final dir = Directory.systemTemp.createTempSync('kelola_sudoers');
        addTearDown(() => dir.deleteSync(recursive: true));
        flavors.forEach((name, sudo) {
          for (final pkg in packageManagers) {
            for (final fw in FirewallBackend.values) {
              final f = facts(pkg: pkg, fw: fw);
              final file = File('${dir.path}/${pkg.name}-${fw.name}')
                ..writeAsStringSync(fullSpec(f, sudo).content);
              final result = Process.runSync(visudo, ['-c', '-f', file.path]);
              expect(
                result.exitCode,
                0,
                reason: '$name ${file.path}: '
                    '${result.stdout}${result.stderr}\n'
                    '${file.readAsStringSync()}',
              );
            }
          }
          // M52d: syslog reads, Docker, and exact unit lines with a `:`.
          const units = ['nginx.service', 'dbus-org.freedesktop:1.service'];
          final f = facts().copyWith(hasJournald: false, runtimes: ['docker']);
          final file = File('${dir.path}/m52d')
            ..writeAsStringSync(
              buildKelolaSudoersSpec(
                user: 'hendr',
                facts: f,
                groups: defaultKelolaSudoersGroups(f, sudo: sudo, units: units),
                sudo: sudo,
                units: units,
              ).content,
            );
          final result = Process.runSync(visudo, ['-c', '-f', file.path]);
          expect(
            result.exitCode,
            0,
            reason: '$name m52d: ${result.stdout}${result.stderr}\n'
                '${file.readAsStringSync()}',
          );
          // M52d: Kubernetes reads for each CLI.
          for (final runtimes in const [
            ['k3s', 'kubectl', 'crictl'],
            ['kubectl'],
            ['crictl'],
          ]) {
            final k = facts().copyWith(runtimes: runtimes);
            final file = File('${dir.path}/k8s-${runtimes.join('-')}')
              ..writeAsStringSync(fullSpec(k, sudo).content);
            final result = Process.runSync(visudo, ['-c', '-f', file.path]);
            expect(
              result.exitCode,
              0,
              reason: '$name k8s: ${result.stdout}${result.stderr}\n'
                  '${file.readAsStringSync()}',
            );
          }
        });
      });
    }

    const paths = ['/usr/sbin/visudo', '/usr/sbin/visudo.ws'];
    check(
      'classic visudo',
      // Prints its own name: `visudo version` or `visudo.ws version`.
      find(paths, (v) => RegExp(r'^visudo(\.ws)? version ').hasMatch(v)),
      allFlavors,
    );
    check(
      'sudo-rs visudo',
      find(paths, (v) => v.startsWith('visudo-rs')),
      noRegexFlavors,
    );
  });
}
