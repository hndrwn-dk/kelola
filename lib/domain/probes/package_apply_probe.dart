import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class PackageApplyProbe extends Probe<String> {
  const PackageApplyProbe({
    required this.names,
    required this.securityOnly,
    required this.manager,
  });

  final List<String> names;
  final bool securityOnly;
  final PackageManager manager;

  @override
  String get auditTitle => packageApplyAuditTitle(
        count: names.length,
        securityOnly: securityOnly,
      );

  @override
  String command(HostFacts facts) {
    return PackageCommands.apply(facts.pkg, securityOnly: securityOnly);
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException(
        SudoHintContext(
          kind: SudoHintKind.packages,
          binary: PackageCommands.apply(manager, securityOnly: securityOnly)
              .replaceFirst('sudo -n ', ''),
          verb: securityOnly ? 'security-upgrade' : 'upgrade',
        ),
      );
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return stdout.trim().isEmpty ? 'ok' : stdout.trim();
  }

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(minutes: 15);
}
