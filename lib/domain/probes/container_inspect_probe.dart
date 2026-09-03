import 'package:kelola/domain/containers/container_detail.dart';
import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/containers/container_inspect_parser.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class ContainerInspectProbe extends Probe<ContainerDetail> {
  const ContainerInspectProbe(this.row);

  final ContainerRow row;

  @override
  String get auditTitle => 'Inspected ${row.title}';

  @override
  String command(HostFacts facts) {
    final id = shellSingleQuote(row.id);
    return containerEngineScript(
      engine: row.engine,
      body: '''
echo "---INSPECT---"
run inspect $id
echo "---STATS---"
run stats --no-stream --format '{{json .}}' $id
echo "---LOGS---"
run logs --tail 80 --timestamps $id
''',
    );
  }

  @override
  ContainerDetail parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext.container(
          engine: row.engine,
          verb: 'inspect',
          target: row.title,
        ),
      );
    }
    return const ContainerInspectParser().parse(stdout, stderr, exitCode);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 25);
}
