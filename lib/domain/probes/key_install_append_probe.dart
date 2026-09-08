import 'package:kelola/domain/enrollment/key_install_script.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class KeyInstallAppendProbe extends Probe<KeyInstallAppendResult> {
  const KeyInstallAppendProbe({
    required this.keyBody,
    required this.fullLine,
  });

  final String keyBody;
  final String fullLine;

  @override
  String command(HostFacts facts) =>
      buildKeyInstallRemoteCommand(keyBody: keyBody, fullLine: fullLine);

  @override
  KeyInstallAppendResult parse(String stdout, String stderr, int exitCode) =>
      parseKeyInstallAppendResult(exitCode: exitCode, stdout: stdout);

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  String get auditTitle => 'Install Kelola public key';

  @override
  Duration get timeout => const Duration(seconds: 30);
}
