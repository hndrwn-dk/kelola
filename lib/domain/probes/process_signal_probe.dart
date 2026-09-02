import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum ProcessSignal { term, kill }

bool isProtectedProcess(ProcessRow row) {
  if (row.pid <= 1) {
    return true;
  }
  final c = row.command.toLowerCase();
  return c == 'sshd' || c == 'ssh' || c.startsWith('sshd:') || c == 'dropbear';
}

class ProcessSignalProbe extends Probe<String> {
  const ProcessSignalProbe({
    required this.pid,
    required this.signal,
    required this.commandName,
  });

  final int pid;
  final ProcessSignal signal;
  final String commandName;

  @override
  String command(HostFacts facts) {
    if (pid <= 1) {
      return 'echo ---BLOCKED---; exit 2';
    }
    final comm = commandName.toLowerCase();
    if (comm == 'sshd' || comm == 'ssh' || comm.startsWith('sshd:')) {
      return 'echo ---BLOCKED---; exit 2';
    }
    final sig = signal == ProcessSignal.kill ? 'KILL' : 'TERM';
    final q = shellSingleQuote('$pid');
    return '''
LC_ALL=C
if [ $pid -le 1 ]; then echo ---BLOCKED---; exit 2; fi
sudo -n kill -s $sig $q
ec=\$?
if [ \$ec -ne 0 ]; then
  kill -s $sig $q
  ec=\$?
fi
echo "---DONE---"
exit \$ec
''';
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---BLOCKED---')) {
      throw KelolaException('Refused to signal PID 1 or sshd.');
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException();
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'kill exit $exitCode' : stderr.trim(),
      );
    }
    return 'sent ${signal == ProcessSignal.kill ? 'SIGKILL' : 'SIGTERM'} to $pid';
  }

  @override
  String get auditTitle {
    final sig = signal == ProcessSignal.kill ? 'SIGKILL' : 'SIGTERM';
    return 'Sent $sig to $commandName ($pid)';
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk =>
      signal == ProcessSignal.kill ? RiskLevel.destructive : RiskLevel.mutate;
}

class ProcessInspectProbe extends Probe<ProcessInspect> {
  const ProcessInspectProbe(this.pid);

  final int pid;

  @override
  String get auditTitle => 'Inspected process $pid';

  @override
  String command(HostFacts facts) {
    final q = shellSingleQuote('$pid');
    return '''
LC_ALL=C
echo "---FD---"
ls -l /proc/$q/fd 2>/dev/null | head -n 40 || echo "(unreadable)"
echo "---CWD---"
readlink /proc/$q/cwd 2>/dev/null || true
echo "---EXE---"
readlink /proc/$q/exe 2>/dev/null || true
''';
  }

  @override
  ProcessInspect parse(String stdout, String stderr, int exitCode) {
    return ProcessInspect(
      fds: _section(stdout, 'FD').trim(),
      cwd: _section(stdout, 'CWD').trim(),
      exe: _section(stdout, 'EXE').trim(),
    );
  }

  static String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return '';
    }
    final rest = stdout.substring(i + marker.length);
    final next = rest.indexOf('---');
    return next < 0 ? rest : rest.substring(0, next);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class ProcessInspect {
  const ProcessInspect({
    required this.fds,
    required this.cwd,
    required this.exe,
  });

  final String fds;
  final String cwd;
  final String exe;
}
