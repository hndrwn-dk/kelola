import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/unit_sudoers_grant.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';

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

/// Adds one service action to [kelolaUnitSudoersPath]. The sudo password
/// arrives on stdin only.
class UnitSudoersGrantProbe extends Probe<void> {
  const UnitSudoersGrantProbe(this.grant);

  final UnitSudoersGrant grant;

  @override
  String get auditTitle => 'Allowed ${grant.action} without a password';

  @override
  String auditCommand(HostFacts facts) =>
      'kelola-sudoers-unit-grant $kelolaUnitSudoersPath ${grant.lineHash}';

  @override
  String command(HostFacts facts) => buildUnitGrantScript(grant);

  @override
  void parse(String stdout, String stderr, int exitCode) {
    if (exitCode == 0 && stdout.contains(unitGrantOkMarker)) {
      return;
    }
    final err = stderr.trim();
    throw KelolaException(err.isEmpty ? 'Could not add the sudo rule' : err);
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 45);
}

/// Adds a lens's exact read rules to [kelolaWebSudoersPath] (M52 §7b). The
/// sudo password arrives on stdin only.
class WebSudoersGrantProbe extends Probe<void> {
  const WebSudoersGrantProbe(this.grant);

  final WebSudoersGrant grant;

  String get _label => grant.id == ServiceId.apache ? 'Apache' : 'nginx';

  @override
  String get auditTitle => 'Allowed $_label lens reads without a password';

  @override
  String auditCommand(HostFacts facts) =>
      'kelola-sudoers-web-grant $kelolaWebSudoersPath ${grant.linesHash}';

  @override
  String command(HostFacts facts) => buildWebGrantScript(grant);

  @override
  void parse(String stdout, String stderr, int exitCode) {
    if (exitCode == 0 && stdout.contains(webGrantOkMarker)) {
      return;
    }
    final err = stderr.trim();
    throw KelolaException(err.isEmpty ? 'Could not add the sudo rules' : err);
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
