import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('reboot and poweroff are destructive sudo -n', () {
    const reboot = HostActionProbe(HostVerb.reboot);
    expect(reboot.command(HostFacts.undiscovered), 'sudo -n reboot');
    expect(reboot.risk, RiskLevel.destructive);
    const off = HostActionProbe(HostVerb.poweroff);
    expect(off.command(HostFacts.undiscovered), 'sudo -n poweroff');
    expect(off.risk, RiskLevel.destructive);
  });

  test('drop caches uses sudo -n and is mutate', () {
    const p = HostActionProbe(HostVerb.dropCaches);
    expect(p.risk, RiskLevel.mutate);
    expect(p.command(HostFacts.undiscovered), contains('drop_caches'));
    expect(p.command(HostFacts.undiscovered), contains('sudo -n'));
  });

  test('sudo password required becomes SudoRequiredException', () {
    const probe = HostActionProbe(HostVerb.reboot);
    expect(
      () => probe.parse('', 'sudo: a password is required', 1),
      throwsA(isA<SudoRequiredException>()),
    );
  });

  test('sudo interactive authentication required becomes SudoRequiredException',
      () {
    const probe = HostActionProbe(HostVerb.reboot);
    expect(
      () => probe.parse(
        '',
        'sudo: interactive authentication is required',
        1,
      ),
      throwsA(isA<SudoRequiredException>()),
    );
  });
}
