import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class CommandRunnerResult {
  const CommandRunnerResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
}

/// One-shot SSH exec. Not a PTY, not a login shell, not M9.
class CommandRunnerProbe extends Probe<CommandRunnerResult> {
  const CommandRunnerProbe(this.line);

  final String line;

  @override
  String command(HostFacts facts) {
    return 'TERM=dumb /bin/sh -c ${shellSingleQuote(line)}';
  }

  @override
  CommandRunnerResult parse(String stdout, String stderr, int exitCode) {
    return CommandRunnerResult(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
    );
  }

  @override
  String get auditTitle {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return 'Ran command';
    }
    return 'Ran ${trimmed.split(RegExp(r'\s+')).first}';
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 45);
}

const commandRunnerEmptyCopy =
    'One command at a time over SSH exec. No PTY. vim, top, and less will not work.';

String formatCommandRun(String line, CommandRunnerResult result) {
  final buf = StringBuffer('\$ $line\n');
  _appendOut(buf, result.stdout);
  _appendOut(buf, result.stderr);
  buf.write('exit ${result.exitCode}');
  return buf.toString();
}

void _appendOut(StringBuffer buf, String text) {
  if (text.isEmpty) {
    return;
  }
  buf.write(text);
  if (!text.endsWith('\n')) {
    buf.write('\n');
  }
}
