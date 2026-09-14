import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/snippet_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('execs via TERM=dumb /bin/sh -c, never a login shell', () {
    final probe = CommandRunnerProbe('ls -la');
    final cmd = probe.command(HostFacts.undiscovered);
    expect(cmd, "TERM=dumb /bin/sh -c 'ls -la'");
    expect(cmd, isNot(contains('bash -l')));
    expect(cmd, isNot(contains('sh -l')));
    expect(cmd, isNot(contains('--login')));
    expect(probe.risk, RiskLevel.mutate);
    expect(probe.needsSudo, isFalse);
  });

  test('quotes the user line so metacharacters stay inside sh -c', () {
    final probe = CommandRunnerProbe("echo 'hi'");
    expect(
      probe.command(HostFacts.undiscovered),
      "TERM=dumb /bin/sh -c 'echo '\\''hi'\\'''",
    );
  });

  test('keeps non-zero exit instead of throwing', () {
    const probe = CommandRunnerProbe('false');
    final result = probe.parse('out\n', 'err\n', 1);
    expect(result.stdout, 'out\n');
    expect(result.stderr, 'err\n');
    expect(result.exitCode, 1);
  });

  test('transcript is command, output, then exit — not a prompt', () {
    const result = CommandRunnerResult(
      stdout: 'file.txt\n',
      stderr: '',
      exitCode: 0,
    );
    expect(formatCommandRun('ls', result), '\$ ls\nfile.txt\nexit 0');
  });

  test('a dropped connection never yields an exit number line', () {
    const probe = SnippetProbe(name: 'df', commandLine: 'df -PT /');
    final result = commandRunFromExec(
      stdout: '',
      stderr: 'Connection closed by remote host',
      exitCode: null,
    );
    final parsed = parseProbeExec(
      probe,
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: null,
    );
    expect(parsed.exitCode, isNull);
    final text = formatCommandRun(probe.commandLine, parsed);
    expect(text, endsWith('no exit status'));
    expect(
      text.split('\n').where((line) => RegExp(r'^exit -?\d+$').hasMatch(line)),
      isEmpty,
    );
    expect(text, isNot(contains('-1')));
  });

  test('a real exit status is still the number', () {
    final result = commandRunFromExec(
      stdout: '',
      stderr: 'missing',
      exitCode: 1,
    );
    expect(formatCommandRun('false', result), endsWith('exit 1'));
  });

  test('empty pane copy is a command runner, not a terminal', () {
    expect(commandRunnerEmptyCopy.toLowerCase(), contains('no pty'));
    expect(commandRunnerEmptyCopy.toLowerCase(), contains('vim'));
    expect(commandRunnerEmptyCopy.toLowerCase(), isNot(contains('connected')));
  });

  // Command runner must stay exec-only (no PTY). Journal follow is the one
  // exception: without a PTY, journalctl -f gets EPOLLHUP on a pipe and exits
  // immediately (0b5b269). Counting SSHPtyConfig == 1 catches a second,
  // ungated allocation elsewhere in session_pool.
  test('session pool allocates a PTY only for journal follow', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, isNot(contains('.shell(')));
    expect(src, isNot(contains('openShell')));
    expect(src, isNot(contains('interactive shell')));

    final ptyMatches = RegExp(r'SSHPtyConfig').allMatches(src);
    expect(ptyMatches.length, 1);

    final gated = RegExp(
      r'journalFollowRequiresPty\s*\?\s*const\s+SSHPtyConfig\s*\(\s*\)\s*:\s*null',
    );
    expect(gated.hasMatch(src), isTrue);
  });
}
