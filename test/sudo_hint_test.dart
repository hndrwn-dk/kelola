import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/probes/firewall_list_probe.dart';
import 'package:kelola/domain/probes/package_apply_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

void expectNoBareSudoersBinaries(String text) {
  expect(text, isNot(contains('/bin/sh')));
  expect(text, isNot(contains('/usr/bin/sh')));
  expect(text, isNot(matches(RegExp(r'/usr/bin/systemctl(?!\s+\S)'))));
  expect(text, isNot(matches(RegExp(r'/usr/bin/docker(?!\s+\S)'))));
  expect(text, isNot(contains('NOPASSWD: ALL')));
  expect(
    text,
    isNot(matches(RegExp(r'/usr/sbin/(iptables-save|reboot|poweroff)(?!\s+"")'))),
  );
}

void main() {
  test('generic hint never suggests a shell or bare mutate binaries', () {
    final hint = kelolaSudoHint(user: 'hendra');
    expectNoBareSudoersBinaries(hint.snippet);
    expectNoBareSudoersBinaries(hint.body);
    expect(hint.snippet, contains('visudo -f /etc/sudoers.d/kelola'));
    expect(hint.body.toLowerCase(), contains('journal'));
    expect(hint.body, contains('systemctl --user'));
  });

  test('nginx restart hint is that unit only, with visudo and polkit', () {
    final hint = kelolaSudoHint(
      user: 'hendra',
      context: SudoHintContext.systemd(
        unit: 'nginx.service',
        verb: 'restart',
      ),
    );
    expectNoBareSudoersBinaries(hint.snippet);
    expect(hint.snippet, contains('systemctl restart nginx.service'));
    expect(hint.snippet, contains('visudo -f /etc/sudoers.d/kelola'));
    expect(hint.snippet, contains('org.freedesktop.systemd1.manage-units'));
    expect(hint.snippet, contains('nginx.service'));
    expect(hint.snippet, isNot(contains('sshd.service')));
    expect(hint.snippet, contains('/etc/polkit-1/rules.d/49-kelola.rules'));
    expect(hint.snippet, isNot(contains('NOPASSWD: ALL')));
  });

  group('systemd hints', () {
    SudoHint hintFor({required String unit, String verb = 'restart'}) {
      return kelolaSudoHint(
        user: 'hendra',
        context: SudoHintContext.systemd(unit: unit, verb: verb),
      );
    }

    test('never carry a host-supplied name that is not one unit', () {
      for (final unit in [
        'x.service,/bin/sh',
        'x.service, /bin/sh',
        '*',
        'x*.service',
        'x".service',
        '" || true || "',
        'x service',
        'x\nservice',
        'x.service\nhendra ALL=(ALL) NOPASSWD: ALL',
        '-x.service',
        '--root=/tmp',
        '/tmp/x.service',
        '../x.service',
        'x\r.service',
        '',
      ]) {
        final hint = hintFor(unit: unit);
        expect(hint.snippet, isNot(contains('NOPASSWD')), reason: unit);
        expect(hint.snippet, isNot(contains('polkit')), reason: unit);
        expect(
          hint.snippet,
          contains('# This command cannot be written as a safe sudoers rule.'),
          reason: unit,
        );
        if (unit.isNotEmpty) {
          expect(hint.body, isNot(contains(unit)), reason: unit);
        }
      }
    });

    test('allow only the verbs the app sends', () {
      for (final verb in ['edit', 'restart x', 'restart,/bin/sh', '"', '*']) {
        final hint = hintFor(unit: 'nginx.service', verb: verb);
        expect(hint.snippet, isNot(contains('NOPASSWD')), reason: verb);
        expect(hint.snippet, isNot(contains('polkit')), reason: verb);
      }
    });

    test('accept what the sudoers service rule accepts', () {
      for (final unit in ['nginx.service', 'getty@tty1.service', 'a_b-c.mount']) {
        expect(isSudoersSafeUnitName(unit), isTrue, reason: unit);
        expect(
          hintFor(unit: unit).snippet,
          contains('NOPASSWD: /usr/bin/systemctl restart $unit\n'),
          reason: unit,
        );
      }
    });

    test('escape a systemd-escaped name for sudoers and for polkit', () {
      final snippet = hintFor(unit: r'foo\x2dbar:1.service').snippet;
      expect(
        snippet,
        contains(r'NOPASSWD: /usr/bin/systemctl restart foo\\x2dbar\:1.service'),
      );
      expect(
        snippet,
        contains(r'action.lookup("unit") == "foo\\x2dbar:1.service"'),
      );
    });

    test('a trailing backslash cannot open the polkit string', () {
      expect(
        hintFor(unit: r'x\').snippet,
        contains(r'action.lookup("unit") == "x\\" &&'),
      );
    });
  });

  group('hint wire form', () {
    SudoHintContext roundTrip(SudoHintContext context) {
      return SudoHintContext.tryParse(
        SudoRequiredException(context).toString(),
      );
    }

    test('a newline in target cannot add a field', () {
      const target = 'x\nkind=firewall\nbinary=/bin/sh';
      final parsed = roundTrip(
        SudoHintContext.container(
          engine: 'docker',
          verb: 'restart',
          target: target,
        ),
      );
      expect(parsed.kind, SudoHintKind.container);
      expect(parsed.binary, '/usr/bin/docker');
      expect(parsed.verb, 'restart');
      expect(parsed.target, target);

      final hint = kelolaSudoHint(user: 'hendra', context: parsed);
      expect(hint.snippet, isNot(contains('NOPASSWD')));
      expect(hint.snippet, isNot(contains('/bin/sh')));
      expect(hint.body, isNot(contains('/bin/sh')));
    });

    test('a newline in unit cannot add a field', () {
      const unit = 'x.service\nkind=firewall\nbinary="/bin/sh"\nverb="edit"';
      final parsed = roundTrip(
        SudoHintContext.systemd(unit: unit, verb: 'restart'),
      );
      expect(parsed.kind, SudoHintKind.systemd);
      expect(parsed.binary, 'systemctl');
      expect(parsed.verb, 'restart');
      expect(parsed.unit, unit);

      final hint = kelolaSudoHint(user: 'hendra', context: parsed);
      expect(hint.snippet, isNot(contains('NOPASSWD')));
      expect(hint.snippet, isNot(contains('/bin/sh')));
    });

    test('every field survives the trip unchanged', () {
      const context = SudoHintContext(
        kind: SudoHintKind.packages,
        unit: 'a=b "c" \\ é\n\r\t',
        verb: 'x=1',
        binary: r'/usr/bin/apt-get -o Dpkg::Options::=--force-confold upgrade',
        target: 'lone \ud800 surrogate',
      );
      final parsed = roundTrip(context);
      expect(parsed.kind, context.kind);
      expect(parsed.unit, context.unit);
      expect(parsed.verb, context.verb);
      expect(parsed.binary, context.binary);
      expect(parsed.target, context.target);
    });

    test('a repeated field gives the generic hint', () {
      final marker = SudoHintContext.wireMarker;
      for (final wire in [
        'kind="packages"\nkind="firewall"\nbinary="/bin/sh"',
        'kind="firewall"\nbinary="/usr/sbin/ufw status"\nbinary="/bin/sh"',
      ]) {
        final parsed = SudoHintContext.tryParse('sudo\n$marker\n$wire');
        expect(parsed.kind, SudoHintKind.generic, reason: wire);
        expect(parsed.binary, isNull, reason: wire);
      }
    });

    test('a value that is not one encoded string gives the generic hint', () {
      final marker = SudoHintContext.wireMarker;
      for (final value in ['/bin/sh', '"open', '1', 'null', '["x"]', '']) {
        final parsed = SudoHintContext.tryParse(
          'sudo\n$marker\nkind="firewall"\nbinary=$value',
        );
        expect(parsed.kind, SudoHintKind.generic, reason: value);
        expect(parsed.binary, isNull, reason: value);
      }
    });

    test('error text from a host cannot act as the wire form', () {
      for (final marker in ['---KELOLA_SUDO---', '---KELOLA_SUDO-00---']) {
        for (final binary in ['/bin/sh', '"/bin/sh"']) {
          final stderr = 'sudo: a password is required\n'
              '$marker\nkind="firewall"\nbinary=$binary';
          final message = KelolaException(stderr).toString();
          expect(looksLikeSudoRequired(message), isTrue);

          final parsed = SudoHintContext.tryParse(message);
          expect(parsed.kind, SudoHintKind.generic);
          expect(parsed.binary, isNull);
          expect(
            kelolaSudoHint(user: 'hendra', context: parsed).snippet,
            isNot(contains('/bin/sh')),
          );
        }
      }
    });

    test('the marker is not a fixed string', () {
      expect(
        SudoHintContext.wireMarker,
        matches(RegExp(r'^---KELOLA_SUDO-[0-9a-f]{32}---$')),
      );
    });
  });

  group('container hints', () {
    SudoHint hintFor(String target) {
      return kelolaSudoHint(
        user: 'hendra',
        context: SudoHintContext.container(
          engine: 'docker',
          verb: 'restart',
          target: target,
        ),
      );
    }

    test('name one container', () {
      expect(
        hintFor('web-1.a_b').snippet,
        contains('hendra ALL=(root) NOPASSWD: /usr/bin/docker restart web-1.a_b\n'),
      );
    });

    test('never carry a host-supplied value that is not one name', () {
      for (final target in [
        'x\nhendra ALL=(ALL) NOPASSWD: ALL',
        'x\rkind=firewall',
        'x y',
        '--help',
        '-t 0 x',
        'x,/bin/sh',
        '"',
        '*',
      ]) {
        final hint = hintFor(target);
        expect(hint.snippet, isNot(contains('NOPASSWD')), reason: target);
        expect(hint.body, isNot(contains(target)), reason: target);
      }
    });
  });

  test('a control character in a command gives no rule', () {
    for (final binary in ['/usr/bin/dnf x\ny', '/usr/bin/dnf x\ry']) {
      final hint = kelolaSudoHint(
        user: 'hendra',
        context: SudoHintContext(kind: SudoHintKind.packages, binary: binary),
      );
      expect(hint.snippet, isNot(contains('NOPASSWD')), reason: binary);
    }
  });

  test('drop_caches hint is the one exact sysctl line, never a shell', () {
    final hint = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext.dropCaches(),
    );
    expectNoBareSudoersBinaries(hint.snippet);
    expect(
      hint.snippet,
      contains('hendra ALL=(root) NOPASSWD: $kelolaDropCachesCommand\n'),
    );
    expect(hint.snippet, isNot(contains('sh -c')));
    expect(hint.body, contains('Enable Kelola sudo'));
  });

  test('footer sudo sentence reuses the title and names mutate failure', () {
    expect(sudoMutateWillFail, '$sudoRequiredTitle — mutate actions will fail');
  });

  test('detects SudoRequiredException and interactive sudo strings', () {
    expect(looksLikeSudoRequired(SudoRequiredException()), isTrue);
    expect(
      looksLikeSudoRequired('sudo: interactive authentication is required'),
      isTrue,
    );
    expect(looksLikeSudoRequired('sudo: a password is required'), isTrue);
    expect(looksLikeSudoRequired('Timed out waiting for SSH login.'), isFalse);
    expect(looksLikeSudoRequired('Host missing'), isFalse);
  });

  test('service control is honest and never invents unit counts', () {
    expect(
      serviceControlLabel(readOnly: true, sudoNeedsPassword: false),
      'none — read only',
    );
    expect(
      serviceControlLabel(readOnly: false, sudoNeedsPassword: true),
      'none — read only',
    );
    expect(
      serviceControlLabel(readOnly: false, sudoNeedsPassword: false),
      'sudo',
    );
    expect(serviceControlLabel(readOnly: false, sudoNeedsPassword: false),
        isNot(contains('units')));
  });

  test('package and firewall hints name the command, never a shell', () {
    final pkg = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext(
        kind: SudoHintKind.packages,
        binary: '/usr/bin/apt-get -y -o Dpkg::Options::=--force-confold upgrade',
      ),
    );
    expectNoBareSudoersBinaries(pkg.snippet);
    expect(pkg.snippet, contains('/usr/bin/apt-get -y'));
    expect(pkg.snippet, contains(r'Dpkg\:\:Options\:\:=--force-confold'));

    final fw = kelolaSudoHint(
      user: 'hendra',
      context: const SudoHintContext(
        kind: SudoHintKind.firewall,
        binary: '/usr/bin/firewall-cmd --add-port=8080/tcp',
      ),
    );
    expectNoBareSudoersBinaries(fw.snippet);
    expect(fw.snippet, contains('firewall-cmd --add-port=8080/tcp'));
  });

  group('package hints', () {
    SudoHintContext contextFor(PackageManager manager, List<String> names) {
      try {
        PackageApplyProbe(
          names: names,
          securityOnly: false,
          manager: manager,
        ).parse('', 'sudo: a password is required', 1);
      } on SudoRequiredException catch (e) {
        return e.context;
      }
      throw StateError('expected SudoRequiredException');
    }

    test('name the package without the shell quotes', () {
      final hint = kelolaSudoHint(
        user: 'hendra',
        context: contextFor(PackageManager.dnf, ['openssl']),
      );
      expect(
        hint.snippet,
        contains('hendra ALL=(root) NOPASSWD: /usr/bin/dnf upgrade -y openssl\n'),
      );
      expect(hint.snippet, isNot(contains("'")));
    });

    test('escape what would end the sudoers command', () {
      final hint = kelolaSudoHint(
        user: 'hendra',
        context: contextFor(PackageManager.apt, ['libc6:i386']),
      );
      expect(hint.snippet, contains(r'--only-upgrade libc6\:i386'));
      expect(hint.snippet, contains(r'Dpkg\:\:Options\:\:=--force-confold'));
    });

    test('never carry a host-supplied name that is not one package', () {
      for (final manager in PackageManager.values) {
        for (final name in [
          '*',
          'x -o y',
          '-c/tmp/x',
          if (manager == PackageManager.dnf) 'evil.rpm',
        ]) {
          final snippet = kelolaSudoHint(
            user: 'hendra',
            context: contextFor(manager, [name]),
          ).snippet;
          expect(snippet, isNot(contains(name)), reason: '$manager $name');
        }
      }
    });

    test('never suggest a pattern for a host-supplied value', () {
      final hint = kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(
          kind: SudoHintKind.container,
          binary: '/usr/bin/docker',
          verb: 'restart',
          target: '*',
        ),
      );
      expect(hint.snippet, isNot(contains('NOPASSWD')));
    });

    test('never suggest a refusal or a wildcard', () {
      for (final manager in PackageManager.values) {
        final snippet = kelolaSudoHint(
          user: 'hendra',
          context: contextFor(manager, ['openssl']),
        ).snippet;
        expect(snippet, isNot(contains('NOPASSWD: !')));
        expect(snippet, isNot(contains('*')));
      }
    });
  });

  test('a sudo-rs refusal reads as sudo needing a password', () {
    expect(
      looksLikeSudoPasswordPrompt(
        "sudo: I'm sorry hendra. I'm afraid I can't do that",
      ),
      isTrue,
    );
    expect(
      looksLikeSudoPasswordPrompt('sudo: interactive authentication is required'),
      isTrue,
    );
  });

  group('commands the app runs with no arguments', () {
    test('reboot and poweroff hints allow no arguments', () {
      final reboot = kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(kind: SudoHintKind.hostReboot),
      );
      final poweroff = kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(kind: SudoHintKind.hostPoweroff),
      );
      expectNoBareSudoersBinaries(reboot.snippet);
      expectNoBareSudoersBinaries(poweroff.snippet);
      expect(
        reboot.snippet,
        contains('hendra ALL=(root) NOPASSWD: /usr/sbin/reboot ""\n'),
      );
      expect(
        poweroff.snippet,
        contains('hendra ALL=(root) NOPASSWD: /usr/sbin/poweroff ""\n'),
      );
    });

    test('iptables list hint allows no arguments and reads cleanly', () {
      late SudoHintContext context;
      try {
        const FirewallListProbe().parse(
          '---FW---\niptables\n',
          'sudo: a password is required',
          1,
        );
        fail('expected SudoRequiredException');
      } on SudoRequiredException catch (e) {
        context = e.context;
      }

      final roundTripped = SudoHintContext.tryParse(
        '${SudoHintContext.wireMarker}\n${context.toWire()}',
      );
      for (final ctx in [context, roundTripped]) {
        final hint = kelolaSudoHint(user: 'hendra', context: ctx);
        expectNoBareSudoersBinaries(hint.snippet);
        expect(
          hint.snippet,
          contains('hendra ALL=(root) NOPASSWD: /usr/sbin/iptables-save ""\n'),
        );
        expect(hint.body, contains('so /usr/sbin/iptables-save failed.'));
      }
    });

    test('commands with arguments keep them unchanged', () {
      final hint = kelolaSudoHint(
        user: 'hendra',
        context: const SudoHintContext(
          kind: SudoHintKind.firewall,
          binary: '/usr/sbin/nft -j list ruleset',
        ),
      );
      expect(
        hint.snippet,
        contains('hendra ALL=(root) NOPASSWD: /usr/sbin/nft -j list ruleset\n'),
      );
    });
  });
}
