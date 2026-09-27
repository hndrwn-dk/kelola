import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum ComposeVerb { up, down, restart, pull }

class ComposeActionProbe extends Probe<String> {
  const ComposeActionProbe({
    required this.project,
    required this.workingDir,
    required this.verb,
    this.engine = 'docker',
  });

  final String project;
  final String workingDir;
  final ComposeVerb verb;
  final String engine;

  @override
  String get auditTitle => switch (verb) {
    ComposeVerb.up => 'Started compose $project',
    ComposeVerb.down => 'Took down compose $project',
    ComposeVerb.restart => 'Restarted compose $project',
    ComposeVerb.pull => 'Pulled compose $project',
  };

  @override
  String command(HostFacts facts) {
    if (workingDir.trim().isEmpty) {
      return 'echo ---NO_COMPOSE_DIR---; exit 1';
    }
    final p = shellSingleQuote(project);
    final dir = shellSingleQuote(workingDir);
    final action = switch (verb) {
      ComposeVerb.up => 'up -d',
      ComposeVerb.down => 'down',
      ComposeVerb.restart => 'restart',
      ComposeVerb.pull => 'pull',
    };
    if (engine == 'podman') {
      return 'LC_ALL=C podman-compose -p $p --project-directory $dir $action';
    }
    return '''
LC_ALL=C
if docker compose version >/dev/null 2>&1; then
  docker compose -p $p --project-directory $dir $action
else
  docker-compose -p $p --project-directory $dir $action
fi
''';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NO_COMPOSE_DIR---')) {
      throw KelolaException(
        'No compose working directory label on this stack. Kelola will not guess a path.',
      );
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(verb: verb.name, target: project),
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
  bool get needsSudo => false;

  @override
  RiskLevel get risk =>
      verb == ComposeVerb.down ? RiskLevel.destructive : RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 120);
}
