import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';

void main() {
  test('sudo -n password prompt becomes SudoRequiredException', () {
    const probe = UnitActionProbe(
      unitName: 'cron.service',
      verb: UnitVerb.restart,
    );
    expect(
      () => probe.parse(
        '',
        'sudo: a password is required',
        1,
      ),
      throwsA(isA<SudoRequiredException>()),
    );
  });

  test('nginx restart sudo failure carries that unit as hint context', () {
    const probe = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.restart,
    );
    expect(
      () => probe.parse('', 'sudo: a password is required', 1),
      throwsA(
        isA<SudoRequiredException>()
            .having((e) => e.context.unit, 'unit', 'nginx.service')
            .having((e) => e.context.verb, 'verb', 'restart'),
      ),
    );
  });

  test('sudo interactive authentication required becomes SudoRequiredException',
      () {
    const probe = UnitActionProbe(
      unitName: 'cron.service',
      verb: UnitVerb.restart,
    );
    expect(
      () => probe.parse(
        '',
        'sudo: interactive authentication is required',
        1,
      ),
      throwsA(isA<SudoRequiredException>()),
    );
  });

  test('systemd action uses non-interactive sudo', () {
    const facts = HostFacts(
      osId: 'ubuntu',
      osVersionId: '26.04',
      init: InitSystem.systemd,
      systemdVersion: 257,
      pkg: PackageManager.apt,
      fw: FirewallBackend.ufw,
      hasJournald: true,
      journalReadable: true,
      arch: 'x86_64',
    );
    const probe = UnitActionProbe(
      unitName: "app's.service",
      verb: UnitVerb.restart,
    );
    expect(probe.command(facts), contains("sudo -n systemctl restart"));
    expect(probe.command(facts), contains("---VERIFY---"));
    expect(probe.command(facts), contains("'app'\\''s.service'"));
  });

  test('parses verified ActiveState after the action', () {
    const probe = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.stop,
    );
    final result = probe.parse(
      '---VERIFY---\nActiveState=inactive\nSubState=dead\nMainPID=0\nResult=success\n',
      '',
      0,
    );
    expect(result.ok, isTrue);
    expect(result.activeState, 'inactive');
    expect(result.mismatch, isFalse);
  });

  test('stop that leaves the unit active is a mismatch', () {
    const probe = UnitActionProbe(
      unitName: 'nginx.service',
      verb: UnitVerb.stop,
    );
    final result = probe.parse(
      '---VERIFY---\nActiveState=active\nSubState=running\nMainPID=441\nResult=success\n',
      '',
      0,
    );
    expect(result.mismatch, isTrue);
  });
}
