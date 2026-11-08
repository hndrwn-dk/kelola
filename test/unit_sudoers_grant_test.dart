import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/sudoers_install_probe.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/service_unit.dart';

UnitSudoersGrant grant({
  String user = 'hendr',
  String verb = 'restart',
  String unit = 'nginx.service',
}) {
  return UnitSudoersGrant.tryCreate(user: user, verb: verb, unit: unit)!;
}

void main() {
  test('the rule is one exact command', () {
    expect(
      grant().line,
      'hendr ALL=(root) NOPASSWD: /usr/bin/systemctl restart nginx.service',
    );
  });

  test('colons in a unit name are escaped for sudoers', () {
    expect(grant(unit: 'a:b.service').line, endsWith(r'restart a\:b.service'));
  });

  test('every lifecycle action can be granted', () {
    for (final verb in ['start', 'stop', 'restart', 'reload']) {
      expect(grant(verb: verb).verb, verb);
    }
  });

  test('actions on unit files are refused', () {
    for (final verb in UnitVerb.values.map((v) => v.name)) {
      final allowed = {'start', 'stop', 'restart', 'reload'}.contains(verb);
      final made = UnitSudoersGrant.tryCreate(
        user: 'hendr',
        verb: verb,
        unit: 'nginx.service',
      );
      expect(made != null, allowed, reason: verb);
    }
    for (final verb in ['enable', 'disable', 'link', 'edit', 'mask', '']) {
      expect(
        UnitSudoersGrant.tryCreate(
          user: 'hendr',
          verb: verb,
          unit: 'nginx.service',
        ),
        isNull,
        reason: verb,
      );
    }
  });

  test('host-supplied unit names cannot change the rule', () {
    for (final unit in [
      '',
      '-H',
      '--root=/x',
      '/tmp/evil.service',
      'a b',
      'a\nroot ALL=(ALL) NOPASSWD: ALL',
      'a,b',
      'a*',
      r'a\x2db.service',
      'a#b',
      'a=b',
    ]) {
      expect(
        UnitSudoersGrant.tryCreate(user: 'hendr', verb: 'restart', unit: unit),
        isNull,
        reason: unit,
      );
    }
  });

  test('odd usernames cannot change the rule', () {
    for (final user in ['', 'a b', 'ALL,', '%sudo', 'a\nb', '#0']) {
      expect(
        UnitSudoersGrant.tryCreate(
          user: user,
          verb: 'restart',
          unit: 'nginx.service',
        ),
        isNull,
        reason: user,
      );
    }
  });

  group('from a failed action', () {
    test('a service failure names its grant', () {
      final hint = SudoHintContext.tryParse(
        SudoRequiredException(
          SudoHintContext.systemd(unit: 'nginx.service', verb: 'restart'),
        ).message,
      );
      final made = UnitSudoersGrant.fromHint(hint, 'hendr');
      expect(made?.action, 'restart nginx.service');
    });

    test('other failures name none', () {
      expect(
        UnitSudoersGrant.fromHint(const SudoHintContext(), 'hendr'),
        isNull,
      );
      expect(
        UnitSudoersGrant.fromHint(
          const SudoHintContext(kind: SudoHintKind.packages),
          'hendr',
        ),
        isNull,
      );
    });

    test('text from a host cannot pose as a failure', () {
      final hint = SudoHintContext.tryParse(
        'kind="systemd"\nunit="nginx.service"\nverb="restart"',
      );
      expect(UnitSudoersGrant.fromHint(hint, 'hendr'), isNull);
    });
  });

  group('install script', () {
    final script = buildUnitGrantScript(grant());

    test('takes the password on stdin only', () {
      expect(script, contains('IFS= read -r SUDO_PASS'));
      expect(script, contains('sudo -S'));
      expect(script, contains('unset SUDO_PASS'));
    });

    test('writes its own file, never the Enable file', () {
      expect(script, contains(kelolaUnitSudoersPath));
      expect(script, isNot(contains("'$kelolaSudoersPath'")));
      // sudo skips files in sudoers.d whose name has a dot or ends in ~.
      expect(kelolaUnitSudoersPath.split('/').last, 'kelola-units');
    });

    test('validates before it installs', () {
      expect(
        script.indexOf('visudo -c -f'),
        lessThan(script.indexOf(' install -o root')),
      );
    });

    test('carries the rule encoded and adds it only once', () {
      expect(script, contains(base64Encode(utf8.encode(grant().line))));
      expect(script, isNot(contains(grant().line)));
      expect(script, contains('grep -qxF'));
    });
  });

  group('probe', () {
    final probe = UnitSudoersGrantProbe(grant());

    test('is an audited mutation that never logs the script', () {
      expect(probe.needsSudo, isTrue);
      expect(probe.auditTitle, contains('restart nginx.service'));
      final audit = probe.auditCommand(HostFacts.undiscovered);
      expect(audit, contains(kelolaUnitSudoersPath));
      expect(audit, isNot(contains('printf')));
    });

    test('fails unless the host confirmed', () {
      expect(() => probe.parse('', 'boom', 1), throwsA(isA<KelolaException>()));
      expect(() => probe.parse('', '', 0), throwsA(isA<KelolaException>()));
      probe.parse(unitGrantOkMarker, '', 0);
    });
  });

  test('sudo flavors that need a grant are the ones without regex', () {
    expect(const SudoRs('0.2.13').supportsArgRegex, isFalse);
    expect(const UnknownSudo().supportsArgRegex, isFalse);
    expect(const ClassicSudo(1, 9, 5).supportsArgRegex, isFalse);
    expect(const ClassicSudo(1, 9, 17).supportsArgRegex, isTrue);
  });

  test('an installed grant does not read as outdated rules', () {
    const sudo = SudoRs('0.2.13');
    final spec = KelolaSudoersSpec(
      user: 'hendr',
      groups: const {KelolaSudoersGroup.hostPower},
      commands: const ['/usr/sbin/reboot ""'],
    );
    expect(sudo.supportsArgRegex, isFalse);
    expect(
      kelolaSudoRulesOutdated(
        listed: const [
          '/usr/sbin/reboot ""',
          '/usr/bin/systemctl restart nginx.service',
        ],
        spec: spec,
      ),
      isFalse,
    );
  });

  test('a host with only grants was never enabled, so is not outdated', () {
    final spec = KelolaSudoersSpec(
      user: 'hendr',
      groups: const {KelolaSudoersGroup.hostPower},
      commands: const ['/usr/sbin/reboot ""'],
    );
    expect(
      kelolaSudoRulesOutdated(
        listed: const ['/usr/bin/systemctl restart nginx.service'],
        spec: spec,
      ),
      isFalse,
    );
    expect(
      kelolaSudoRulesOutdated(listed: const ['/usr/bin/dnf *'], spec: spec),
      isTrue,
    );
  });

  test('the per-service offer is systemd only', () {
    expect(
      File('lib/presentation/widgets/enable_kelola_sudo_flow.dart')
          .readAsStringSync(),
      contains('resolved.init != InitSystem.systemd'),
    );
  });

  test('service sudo errors pass their failure to the flow', () {
    for (final path in [
      'lib/presentation/screens/units_screen.dart',
      'lib/presentation/screens/unit_detail_screen.dart',
      'lib/presentation/widgets/incident_sheet.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains("hint: SudoHintContext.tryParse(_error ?? '')"),
        reason: path,
      );
    }
  });
}
