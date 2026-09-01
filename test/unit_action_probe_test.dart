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
    expect(probe.command(facts), contains("'app'\\''s.service'"));
  });
}
