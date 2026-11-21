import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudoers_install_script.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';

class SudoersInstallProbe extends Probe<SudoersInstallResult> {
  const SudoersInstallProbe({
    required this.spec,
    required this.groupsLabel,
    this.user,
    this.retireUnits = false,
    this.journalGroup = false,
  });

  final KelolaSudoersSpec spec;
  final String groupsLabel;

  /// M52d: the login that [retireUnits] and [journalGroup] act for.
  final String? user;

  /// Fold this login's `kelola-units` lines into the file and remove it.
  final bool retireUnits;

  /// Add this login to `systemd-journal` so logs read without sudo.
  final bool journalGroup;

  @override
  String get auditTitle => 'Installed $kelolaSudoersPath ($groupsLabel)';

  @override
  String auditCommand(HostFacts facts) =>
      'kelola-sudoers-install $kelolaSudoersPath ${spec.contentHash}'
      '${retireUnits ? ' retire=$kelolaUnitSudoersPath' : ''}'
      '${journalGroup ? ' group=$kelolaJournalGroup' : ''}';

  @override
  String command(HostFacts facts) => buildSudoersInstallScript(
    content: spec.content,
    user: user,
    retireUnits: retireUnits,
    journalGroup: journalGroup,
  );

  @override
  SudoersInstallResult parse(String stdout, String stderr, int exitCode) {
    final result = parseSudoersInstallOutput(
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
      expectedContent: spec.content,
    );
    if (!result.ok) {
      throw KelolaException(result.errorSummary ?? 'sudoers install failed');
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

/// Adds a lens's exact read rules to [kelolaWebSudoersPath] (M52 §7b). The
/// sudo password arrives on stdin only. Returns what the host refused to
/// install: cert and log paths ([webGrantSkippedMarker]) and the config test
/// when the server config is not root-controlled ([webGrantConfigMarker]);
/// the other lines were installed. When nothing was installed for those
/// reasons it throws [WebGrantRefusedException].
class WebSudoersGrantProbe extends Probe<WebGrantResult> {
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
  WebGrantResult parse(String stdout, String stderr, int exitCode) {
    final untrusted = webGrantUntrustedBinary(stdout);
    if (untrusted != null) {
      throw KelolaException(webGrantUntrustedCopy(untrusted));
    }
    final skipped = webGrantSkippedPaths(stdout);
    final config = webGrantConfigRefusal(stdout);
    if (exitCode == 0 && stdout.contains(webGrantOkMarker)) {
      return WebGrantResult(skipped: skipped, config: config);
    }
    if (exitCode == webGrantNothingExit &&
        (skipped.isNotEmpty || config != null)) {
      throw WebGrantRefusedException(skipped: skipped, config: config);
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
