import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

void main() {
  test('SSH and network units are lockout-sensitive', () {
    expect(isSelfLockoutUnit('sshd.service'), isTrue);
    expect(isSelfLockoutUnit('ssh.service'), isTrue);
    expect(isSelfLockoutUnit('sshd@0.service'), isTrue);
    expect(isSelfLockoutUnit('NetworkManager.service'), isTrue);
    expect(isSelfLockoutUnit('nginx.service'), isFalse);
  });

  test('stop/disable/restart of ssh is destructive', () {
    expect(isDestructiveUnitAction(UnitVerb.stop, 'ssh.service'), isTrue);
    expect(isDestructiveUnitAction(UnitVerb.restart, 'sshd.service'), isTrue);
    expect(isDestructiveUnitAction(UnitVerb.start, 'ssh.service'), isFalse);
    expect(isDestructiveUnitAction(UnitVerb.stop, 'nginx.service'), isFalse);
  });

  test('UnitActionProbe risk follows lockout', () {
    expect(
      const UnitActionProbe(unitName: 'ssh.service', verb: UnitVerb.stop).risk,
      RiskLevel.destructive,
    );
    expect(
      const UnitActionProbe(unitName: 'cron.service', verb: UnitVerb.restart)
          .risk,
      RiskLevel.mutate,
    );
  });
}
