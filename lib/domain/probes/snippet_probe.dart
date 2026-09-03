import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class SnippetProbe extends Probe<CommandRunnerResult> {
  const SnippetProbe({required this.name, required this.commandLine});

  final String name;
  final String commandLine;

  @override
  String command(HostFacts facts) {
    return 'TERM=dumb /bin/sh -c ${shellSingleQuote(commandLine)}';
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
  String get auditTitle => 'Snippet $name';

  @override
  bool get needsSudo => commandLine.contains('sudo');

  @override
  RiskLevel get risk => classifySnippetCommand(commandLine);

  @override
  Duration get timeout => const Duration(seconds: 45);
}

RiskLevel classifySnippetCommand(String command) {
  final c = command.toLowerCase();
  if (_destructive(c)) {
    return RiskLevel.destructive;
  }
  if (_mutate(c)) {
    return RiskLevel.mutate;
  }
  return RiskLevel.read;
}

bool _destructive(String c) {
  if (RegExp(r'\brm\s+-rf\s+/').hasMatch(c)) {
    return true;
  }
  if (RegExp(r'\b(mkfs|reboot|poweroff|shutdown|shred)\b').hasMatch(c)) {
    return true;
  }
  if (RegExp(r'\bdd\b').hasMatch(c) && c.contains('of=')) {
    return true;
  }
  final lockoutHit = _mentionsLockout(c);
  if (lockoutHit &&
      RegExp(r'\b(stop|disable|restart|mask)\b').hasMatch(c)) {
    return true;
  }
  return false;
}

bool _mutate(String c) {
  if (c.contains('journalctl') && c.contains('vacuum')) {
    return true;
  }
  if (RegExp(
    r'\bsystemctl\s+(start|stop|restart|reload|enable|disable|mask|kill)\b',
  ).hasMatch(c)) {
    return true;
  }
  if (RegExp(
    r'\b(chmod|chown|kill|pkill|apt|dnf|yum|pacman|apk|firewall-cmd|iptables|nft)\b',
  ).hasMatch(c)) {
    return true;
  }
  return false;
}

bool _mentionsLockout(String command) {
  for (final raw in command.split(RegExp(r'\s+'))) {
    final token = raw.replaceAll(RegExp(r'[^a-z0-9@._-]'), '');
    if (token.isEmpty) {
      continue;
    }
    if (isSelfLockoutUnit(token) || isSelfLockoutUnit('$token.service')) {
      return true;
    }
  }
  return false;
}
