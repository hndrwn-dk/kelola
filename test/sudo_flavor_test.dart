import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/sudo_flavor_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';

void main() {
  group('parseSudoFlavor', () {
    test('reads classic sudo from real first lines', () {
      for (final (line, major, minor, patch) in const [
        ('Sudo version 1.8.23', 1, 8, 23),
        ('Sudo version 1.9.5p2', 1, 9, 5),
        ('Sudo version 1.9.9', 1, 9, 9),
        ('Sudo version 1.9.15p5', 1, 9, 15),
        ('Sudo version 1.9.17p2', 1, 9, 17),
      ]) {
        final flavor = parseSudoFlavor('$line\n') as ClassicSudo;
        expect(flavor.major, major);
        expect(flavor.minor, minor);
        expect(flavor.patch, patch);
      }
    });

    test('reads sudo-rs', () {
      final flavor = parseSudoFlavor('sudo-rs 0.2.13-0ubuntu1.2\n');
      expect(flavor, isA<SudoRs>());
      expect((flavor as SudoRs).version, '0.2.13-0ubuntu1.2');
    });

    test('anything else is unknown', () {
      for (final line in const [
        '',
        'sudo: command not found',
        'Sudo 2',
        'Sudo version 1.9.99999999999999999999999999',
      ]) {
        expect(parseSudoFlavor(line), isA<UnknownSudo>(), reason: line);
      }
    });

    test('regex rules start at classic 1.9.10', () {
      bool regex(String line) => parseSudoFlavor(line).supportsArgRegex;
      expect(regex('Sudo version 1.8.31'), isFalse);
      expect(regex('Sudo version 1.9.5p2'), isFalse);
      expect(regex('Sudo version 1.9.9'), isFalse);
      expect(regex('Sudo version 1.9.10'), isTrue);
      expect(regex('Sudo version 1.9.15p5'), isTrue);
      expect(regex('Sudo version 1.10.0'), isTrue);
      expect(regex('Sudo version 2.0.0'), isTrue);
      expect(regex('sudo-rs 9.9.9'), isFalse);
      expect(regex(''), isFalse);
    });
  });

  test('SudoFlavorProbe is a read that needs no sudo', () {
    const probe = SudoFlavorProbe();
    expect(probe.risk, RiskLevel.read);
    expect(probe.needsSudo, isFalse);
    expect(
      probe.command(HostFacts.undiscovered),
      contains('sudo -V 2>/dev/null | head -n 1'),
    );
    expect(probe.parse('Sudo version 1.9.15p5\n', '', 0), isA<ClassicSudo>());
  });

  group('SudoRulesProbe', () {
    const probe = SudoRulesProbe();

    test('is a read that cannot prompt', () {
      expect(probe.risk, RiskLevel.read);
      expect(probe.needsSudo, isFalse);
      expect(probe.command(HostFacts.undiscovered), contains('sudo -n -l'));
    });

    test('splits the flavor from the listing', () {
      final snap = probe.parse(
        'sudo-rs 0.2.13\n'
        '---SUDO_LIST---\n'
        'User u may run the following commands on h:\n'
        '    (root) NOPASSWD: /usr/sbin/reboot ""\n',
        '',
        0,
      );
      expect(snap.sudo, isA<SudoRs>());
      expect(snap.listed, ['/usr/sbin/reboot ""']);
    });

    test('a host that lists nothing has no rules', () {
      final snap = probe.parse('Sudo version 1.9.9\n---SUDO_LIST---\n', '', 0);
      expect(snap.sudo, isA<ClassicSudo>());
      expect(snap.listed, isEmpty);
    });
  });
}
