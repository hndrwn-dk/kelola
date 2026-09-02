import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum ContainerVerb { start, stop, restart, pause, unpause, inspect }

class ContainerActionProbe extends Probe<String> {
  const ContainerActionProbe({
    required this.row,
    required this.verb,
  });

  final ContainerRow row;
  final ContainerVerb verb;

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
      return '''
LC_ALL=C
bin=\$(command -v docker || command -v podman || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
("\$bin" inspect $id 2>/dev/null || sudo -n "\$bin" inspect $id 2>/dev/null) | head -n 80
''';
    }
    final action = verb.name;
    return '''
LC_ALL=C
bin=\$(command -v docker || command -v podman || true)
if [ -z "\$bin" ]; then echo missing engine; exit 1; fi
"\$bin" $action $id 2>/dev/null || sudo -n "\$bin" $action $id
''';
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
      throw SudoRequiredException();
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
    };
    return '$past ${row.title}';
  }

  @override
  bool get needsSudo => verb != ContainerVerb.inspect;

  @override
  RiskLevel get risk =>
      verb == ContainerVerb.inspect ? RiskLevel.read : RiskLevel.mutate;
}
