import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/unit_list_parser.dart';

class UnitListProbe extends Probe<UnitListResult> {
  const UnitListProbe();

  @override
  String command(HostFacts facts) {
    switch (facts.init) {
      case InitSystem.systemd:
        return r'''
LC_ALL=C
SYSTEMD_PAGER=
SYSTEMD_COLORS=0
echo "---UNITS_JSON---"
systemctl list-units --type=service --all --output=json --no-pager 2>/dev/null || true
echo "---UNITS_PLAIN---"
systemctl list-units --type=service --all --no-legend --plain --no-pager 2>/dev/null || true
echo "---FILES_PLAIN---"
systemctl list-unit-files --type=service --no-legend --plain --no-pager 2>/dev/null || true
''';
      case InitSystem.openrc:
        return r'''
LC_ALL=C
echo "---OPENRC---"
rc-status -a 2>/dev/null || true
''';
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return 'echo "---UNSUPPORTED---"';
    }
  }

  @override
  UnitListResult parse(String stdout, String stderr, int exitCode) {
    final supported = !stdout.contains('---UNSUPPORTED---');
    return const UnitListParser().parse(
      stdout: stdout,
      initSupported: supported,
    );
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 25);
}
