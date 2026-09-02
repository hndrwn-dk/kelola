import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';

void main() {
  test('protects pid 1 and sshd', () {
    expect(
      isProtectedProcess(
        const ProcessRow(
          pid: 1,
          ppid: 0,
          user: 'root',
          cpu: 0,
          mem: 0,
          rssKb: 0,
          stat: 'S',
          command: 'systemd',
        ),
      ),
      isTrue,
    );
    expect(
      isProtectedProcess(
        const ProcessRow(
          pid: 412,
          ppid: 1,
          user: 'root',
          cpu: 0,
          mem: 0,
          rssKb: 0,
          stat: 'S',
          command: 'sshd',
        ),
      ),
      isTrue,
    );
  });

  test('pid 1 command is blocked in the probe', () {
    const probe = ProcessSignalProbe(
      pid: 1,
      signal: ProcessSignal.kill,
      commandName: 'systemd',
    );
    expect(probe.command(HostFacts.undiscovered), contains('---BLOCKED---'));
    expect(
      () => probe.parse('---BLOCKED---', '', 2),
      throwsA(isA<KelolaException>()),
    );
  });
}
