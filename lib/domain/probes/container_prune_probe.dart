import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class ContainerPruneProbe extends Probe<String> {
  const ContainerPruneProbe({this.engine = 'docker'});

  final String engine;

  @override
  String get auditTitle => 'Pruned unused images';

  @override
  String command(HostFacts facts) {
    return containerEngineCommand(
      engine: engine,
      args: 'image prune -f',
    );
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.containerPrune,
          binary: engine == 'podman' ? '/usr/bin/podman' : '/usr/bin/docker',
          verb: 'image prune -f',
        ),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? 'prune ok' : stdout.trim();
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 60);
}
