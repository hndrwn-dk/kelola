import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/firewall/firewall_snapshot.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/probes/firewall_apply_probe.dart';
import 'package:kelola/domain/probes/firewall_list_probe.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
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
    final ruleArgs = rule.substring(split + 1).replaceAll(r'\:', ':');
    final allowed = switch (ruleArgs) {
      '""' => args.isEmpty,
      final r when r.startsWith('^') => RegExp(r).hasMatch(args),
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
