import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class UnitActionProbe extends Probe<UnitActionResult> {
  const UnitActionProbe({required this.unitName, required this.verb});

  final String unitName;
  final UnitVerb verb;

  @override
  String command(HostFacts facts) {
    final q = shellSingleQuote(unitName);
    switch (facts.init) {
      case InitSystem.systemd:
        return 'sudo -n systemctl ${verb.name} $q';
      case InitSystem.openrc:
        return switch (verb) {
          UnitVerb.enable => 'sudo -n rc-update add $q default',
          UnitVerb.disable => 'sudo -n rc-update del $q default',
          _ => 'sudo -n rc-service $q ${verb.name}',
        };
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return 'echo unsupported; exit 1';
    }
  }

  @override
  UnitActionResult parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException();
    }
    return UnitActionResult(
      verb: verb,
      unit: unitName,
      exitCode: exitCode,
      stderr: stderr.trim(),
    );
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk {
    if (isDestructiveUnitAction(verb, unitName)) {
      return RiskLevel.destructive;
    }
    switch (verb) {
      case UnitVerb.start:
      case UnitVerb.restart:
      case UnitVerb.reload:
      case UnitVerb.enable:
      case UnitVerb.stop:
      case UnitVerb.disable:
        return RiskLevel.mutate;
    }
  }

  @override
  Duration get timeout => const Duration(seconds: 30);
}
