import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
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
    expect(
      formatCommandRun('ls', result),
      '\$ ls\nfile.txt\nexit 0',
    );
  });

  test('empty pane copy is a command runner, not a terminal', () {
    expect(commandRunnerEmptyCopy.toLowerCase(), contains('no pty'));
    expect(commandRunnerEmptyCopy.toLowerCase(), contains('vim'));
    expect(commandRunnerEmptyCopy.toLowerCase(), isNot(contains('connected')));
  });

  test('session pool no longer requests a PTY or interactive shell', () {
    final src = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    expect(src, isNot(contains('SSHPtyConfig')));
    expect(src, isNot(contains('.shell(')));
    expect(src, isNot(contains('openShell')));
    expect(src, isNot(contains('interactive shell')));
  });
}
