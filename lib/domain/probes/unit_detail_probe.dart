import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/units/shell_quote.dart';
import 'package:kelola/domain/units/unit_detail_parser.dart';

class UnitDetailProbe extends Probe<UnitDetail> {
  const UnitDetailProbe(this.unitName);

  final String unitName;

  @override
  String command(HostFacts facts) {
    final q = shellSingleQuote(unitName);
    switch (facts.init) {
      case InitSystem.systemd:
        return '''
LC_ALL=C
SYSTEMD_PAGER=
SYSTEMD_COLORS=0
echo "---SHOW---"
systemctl show $q --no-pager 2>/dev/null || true
echo "---LOGS---"
journalctl -u $q -n 40 --no-pager -o short-iso 2>/dev/null || true
echo "---DEPS---"
systemctl list-dependencies $q --no-pager --plain 2>/dev/null || true
''';
      case InitSystem.openrc:
        return '''
LC_ALL=C
echo "---SHOW---"
rc-service $q status 2>/dev/null || true
echo "---LOGS---"
echo "---DEPS---"
''';
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return 'echo "---SHOW---"';
    }
  }

  @override
  UnitDetail parse(String stdout, String stderr, int exitCode) {
    return const UnitDetailParser().parse(stdout, unitName);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
