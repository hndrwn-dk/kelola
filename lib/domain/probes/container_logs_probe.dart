import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class ContainerLogsProbe extends Probe<List<String>> {
  const ContainerLogsProbe(this.row, {this.tail = 20});

  final ContainerRow row;
  final int tail;

  @override
  String get auditTitle => 'Read logs for ${row.title}';

  @override
  String command(HostFacts facts) {
    final id = shellSingleQuote(row.id);
    return containerEngineCommand(
      engine: row.engine,
      args: 'logs --tail $tail --timestamps $id',
    );
  }

  @override
  List<String> parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext.container(
          engine: row.engine,
          verb: 'logs',
          target: row.title,
        ),
      );
    }
    if (exitCode != 0 && stdout.trim().isEmpty) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.isNotEmpty)
        .take(20)
        .toList();
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}
