import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum HostVerb { reboot, poweroff, dropCaches }

class HostActionProbe extends Probe<String> {
  const HostActionProbe(this.verb);

  final HostVerb verb;

  @override
  String command(HostFacts facts) {
    switch (verb) {
      case HostVerb.reboot:
        return 'sudo -n reboot';
      case HostVerb.poweroff:
        return 'sudo -n poweroff';
      case HostVerb.dropCaches:
        return "sudo -n sh -c ${shellSingleQuote('sync; echo 3 > /proc/sys/vm/drop_caches')}";
    }
  }

  @override
  String parse(String stdout, String stderr, int exitCode) {
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      throw SudoRequiredException();
    }
    if (exitCode != 0) {
      throw KelolaException(
        stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim(),
      );
    }
    return switch (verb) {
      HostVerb.reboot => 'reboot requested',
      HostVerb.poweroff => 'poweroff requested',
      HostVerb.dropCaches => 'caches flushed',
    };
  }

  @override
  String get auditTitle => switch (verb) {
        HostVerb.reboot => 'Rebooted host',
        HostVerb.poweroff => 'Powered off host',
        HostVerb.dropCaches => 'Dropped caches',
      };

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk =>
      verb == HostVerb.dropCaches ? RiskLevel.mutate : RiskLevel.destructive;

  @override
  Duration get timeout => const Duration(seconds: 20);
}
