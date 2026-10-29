import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';

class SudoersInstallProbe extends Probe<SudoersInstallResult> {
  const SudoersInstallProbe({
    required this.spec,
    required this.groupsLabel,
  });

  final KelolaSudoersSpec spec;
  final String groupsLabel;

  @override
  String get auditTitle => 'Installed $kelolaSudoersPath ($groupsLabel)';

  @override
  String auditCommand(HostFacts facts) =>
      'kelola-sudoers-install $kelolaSudoersPath ${spec.contentHash}';

  @override
  String command(HostFacts facts) =>
      buildSudoersInstallScript(content: spec.content);

  @override
  SudoersInstallResult parse(String stdout, String stderr, int exitCode) {
    final result = parseSudoersInstallOutput(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      expectedContent: spec.content,
    );
    if (!result.ok) {
      throw KelolaException(
        result.errorSummary ?? 'sudoers install failed',
      );
    }
    return result;
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 45);
}

/// Non-destructive existence check (no sudo).
class SudoersFileExistsProbe extends Probe<bool> {
  const SudoersFileExistsProbe();

  @override
  String get auditTitle => 'Checked $kelolaSudoersPath';

  @override
  String command(HostFacts facts) =>
      'if [ -e $kelolaSudoersPath ]; then echo EXISTS; else echo MISSING; fi';

  @override
  bool parse(String stdout, String stderr, int exitCode) {
    return stdout.contains('EXISTS');
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}
