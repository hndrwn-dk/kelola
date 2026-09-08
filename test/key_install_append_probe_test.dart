import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/key_install_append_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  const body = 'AAAA';
  const line = 'ecdsa-sha2-nistp256 AAAA kelola';
  const probe = KeyInstallAppendProbe(keyBody: body, fullLine: line);

  test('command uses sh -s via buildKeyInstallRemoteCommand', () {
    final cmd = probe.command(HostFacts.undiscovered);
    expect(cmd, buildKeyInstallRemoteCommand(keyBody: body, fullLine: line));
    expect(cmd.contains('sh -s'), isTrue);
    expect(cmd.contains('bash'), isFalse);
  });

  test('parse maps exit 3 to alreadyPresent', () {
    final result = probe.parse(
      'HOME_MODE=drwx------\nCREATED_SSH=0\n',
      '',
      3,
    );
    expect(result.kind, KeyInstallAppendKind.alreadyPresent);
    expect(result.homeMode, 'drwx------');
    expect(result.createdSsh, isFalse);
  });

  test('probe metadata', () {
    expect(probe.needsSudo, isFalse);
    expect(probe.risk, RiskLevel.mutate);
    expect(probe.auditTitle, 'Install Kelola public key');
    expect(probe.timeout, const Duration(seconds: 30));
  });
}
