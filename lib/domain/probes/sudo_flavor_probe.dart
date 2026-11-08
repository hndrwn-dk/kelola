import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/sudo_flavor.dart';

const _versionCommand = 'LC_ALL=C sudo -V 2>/dev/null | head -n 1';

/// Reads which sudo the host runs. `sudo -V` needs no privileges.
class SudoFlavorProbe extends Probe<SudoFlavor> {
  const SudoFlavorProbe();

  @override
  String get auditTitle => 'Checked sudo version';

  @override
  String command(HostFacts facts) => _versionCommand;

  @override
  SudoFlavor parse(String stdout, String stderr, int exitCode) =>
      parseSudoFlavor(stdout);

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class SudoRulesSnapshot {
  const SudoRulesSnapshot({required this.sudo, required this.listed});

  final SudoFlavor sudo;
  final List<String> listed;
}

/// Whether [snapshot] differs from what Enable Kelola sudo would write now.
bool sudoRulesOutdated(
  SudoRulesSnapshot snapshot, {
  required String user,
  required HostFacts facts,
}) {
  final sudo = snapshot.sudo;
  return kelolaSudoRulesOutdated(
    listed: snapshot.listed,
    spec: buildKelolaSudoersSpec(
      user: user,
      facts: facts,
      groups: defaultKelolaSudoersGroups(facts, sudo: sudo),
      sudo: sudo,
    ),
  );
}

/// The host's sudo flavor and what `sudo -n -l` lists for this login. `-n`
/// never prompts: with no NOPASSWD rule it fails and lists nothing. The pipe
/// stops classic sudo wrapping long rules to the terminal width.
class SudoRulesProbe extends Probe<SudoRulesSnapshot> {
  const SudoRulesProbe();

  static const _marker = '---SUDO_LIST---';

  @override
  String get auditTitle => 'Checked Kelola sudo rules';

  @override
  String command(HostFacts facts) => '''
$_versionCommand
echo "$_marker"
LC_ALL=C sudo -n -l 2>/dev/null | cat
''';

  @override
  SudoRulesSnapshot parse(String stdout, String stderr, int exitCode) {
    final at = stdout.indexOf(_marker);
    if (at < 0) {
      return const SudoRulesSnapshot(sudo: UnknownSudo(), listed: []);
    }
    return SudoRulesSnapshot(
      sudo: parseSudoFlavor(stdout.substring(0, at)),
      listed: parseSudoListing(stdout.substring(at + _marker.length)),
    );
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}
