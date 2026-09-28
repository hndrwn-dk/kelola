import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/pty/pty_session.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  test('clamps cols and rows to a usable PTY', () {
    expect(clampPtySize(4, 2), (kPtyMinCols, kPtyMinRows));
    expect(clampPtySize(400, 200), (kPtyMaxCols, kPtyMaxRows));
    expect(clampPtySize(80, 24), (80, 24));
  });

  test('open probe is mutate ssh-pty and is never an exec command line', () {
    const probe = PtyBoundaryProbe();
    expect(probe.risk, RiskLevel.mutate);
    expect(probe.auditTitle, kPtyAuditOpen);
    expect(probe.command(HostFacts.undiscovered), kPtyAuditCommand);
    expect(probe.needsSudo, isFalse);
    expect(
      () => probe.parse('', '', 0),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('close audit names duration, not keystrokes', () {
    expect(ptyCloseCommand(const Duration(seconds: 12)), 'ssh-pty 12s');
    expect(const PtyBoundaryProbe(closing: true).auditTitle, kPtyAuditClose);
  });

  test('architecture: PTY shell, Command stays exec, no fleet', () {
    final pool = File('lib/data/ssh/session_pool.dart').readAsStringSync();
    final dash =
        File('lib/presentation/screens/host_dashboard_screen.dart')
            .readAsStringSync();
    final command =
        File('lib/domain/probes/command_runner_probe.dart').readAsStringSync();
    final screen =
        File('lib/presentation/screens/pty_terminal_screen.dart')
            .readAsStringSync();
    expect(pool, contains('openPty'));
    expect(pool, contains('resizeTerminal'));
    expect(command, contains('TERM=dumb'));
    expect(command, contains('Not a PTY'));
    expect(dash, contains('openPtyTerminal'));
    expect(dash, contains("name: 'Command'"));
    expect(screen, contains("acquire('pty')"));
    expect(screen, contains("label: 'Tab'"));
    expect(screen, contains("label: 'Esc'"));
    expect(screen, contains("label: 'Ctrl'"));
    expect(screen, isNot(contains('ProbeScope.fleet')));
    expect(screen, isNot(contains('kubectl exec -it')));
    expect(
      File('lib/domain/pty/pty_session.dart').readAsStringSync(),
      contains('xterm-256color'),
    );
  });
}
