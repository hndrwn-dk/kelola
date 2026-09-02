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
        return '''
sudo -n systemctl ${verb.name} $q
ec=\$?
echo "---VERIFY---"
systemctl show $q -p ActiveState -p SubState -p MainPID -p Result --no-pager 2>/dev/null || true
exit \$ec
''';
      case InitSystem.openrc:
        final action = switch (verb) {
          UnitVerb.enable => 'sudo -n rc-update add $q default',
          UnitVerb.disable => 'sudo -n rc-update del $q default',
          _ => 'sudo -n rc-service $q ${verb.name}',
        };
        return '''
$action
echo "---VERIFY---"
rc-service $q status 2>/dev/null || true
''';
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
    final verify = _section(stdout, 'VERIFY');
    return UnitActionResult(
      verb: verb,
      unit: unitName,
      exitCode: exitCode,
      stderr: stderr.trim(),
      activeState: _prop(verify, 'ActiveState'),
      subState: _prop(verify, 'SubState'),
      mainPid: _prop(verify, 'MainPID'),
      result: _prop(verify, 'Result'),
    );
  }

  static String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return '';
    }
    return stdout.substring(i + marker.length);
  }

  static String _prop(String block, String key) {
    final re = RegExp('^$key=(.*)\$', multiLine: true);
    return re.firstMatch(block)?.group(1)?.trim() ?? '';
  }

  @override
  String get auditTitle {
    final past = switch (verb) {
      UnitVerb.start => 'Started',
      UnitVerb.stop => 'Stopped',
      UnitVerb.restart => 'Restarted',
      UnitVerb.reload => 'Reloaded',
      UnitVerb.enable => 'Enabled',
      UnitVerb.disable => 'Disabled',
    };
    return '$past $unitName';
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
