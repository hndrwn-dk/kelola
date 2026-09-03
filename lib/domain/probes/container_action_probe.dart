import 'package:kelola/domain/containers/container_engine.dart';
import 'package:kelola/domain/containers/container_lockout.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum ContainerVerb { start, stop, restart, pause, unpause, inspect, remove }

class ContainerActionProbe extends Probe<String> {
  const ContainerActionProbe({
    required this.row,
    required this.verb,
    this.sshPort = 22,
  });

  final ContainerRow row;
  final ContainerVerb verb;
  final int sshPort;

  @override
  String command(HostFacts facts) {
    if (row.namespace.isNotEmpty) {
      final ns = shellSingleQuote(row.namespace);
      final name = shellSingleQuote(row.names);
      if (verb == ContainerVerb.inspect) {
        return '''
LC_ALL=C
(kubectl -n $ns describe pod $name 2>/dev/null \\
  || sudo -n kubectl -n $ns describe pod $name 2>/dev/null \\
  || sudo -n k3s kubectl -n $ns describe pod $name 2>/dev/null) | head -n 80
''';
      }
      return 'echo ---K8S---; exit 2';
    }
    final id = shellSingleQuote(row.id);
    if (verb == ContainerVerb.inspect) {
      return containerEngineScript(
        engine: row.engine,
        body: 'run inspect $id | head -n 80',
      );
    }
    final action = verb == ContainerVerb.remove ? 'rm' : verb.name;
    return containerEngineCommand(
      engine: row.engine,
      args: '$action $id',
    );
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---K8S---')) {
      throw KelolaException(
        'Pod lifecycle is not one-tap. Inspect is available; mutate the Deployment in a shell.',
      );
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext.container(
          engine: row.engine,
          verb: verb == ContainerVerb.remove ? 'rm' : verb.name,
          target: row.title,
        ),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? '${verb.name} ok' : stdout.trim();
  }

  @override
  String get auditTitle {
    final past = switch (verb) {
      ContainerVerb.start => 'Started',
      ContainerVerb.stop => 'Stopped',
      ContainerVerb.restart => 'Restarted',
      ContainerVerb.pause => 'Paused',
      ContainerVerb.unpause => 'Unpaused',
      ContainerVerb.inspect => 'Inspected',
      ContainerVerb.remove => 'Removed',
    };
    return '$past ${row.title}';
  }

  @override
  bool get needsSudo => verb != ContainerVerb.inspect;

  @override
  RiskLevel get risk {
    if (verb == ContainerVerb.inspect) {
      return RiskLevel.read;
    }
    if (verb == ContainerVerb.remove ||
        isLockoutContainerAction(verb.name, row, sshPort: sshPort)) {
      return RiskLevel.destructive;
    }
    return RiskLevel.mutate;
  }
}
