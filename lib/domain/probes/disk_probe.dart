import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class DiskProbe extends Probe<List<DiskMount>> {
  const DiskProbe();

  @override
  String command(HostFacts facts) => 'LC_ALL=C df -PT';

  @override
  List<DiskMount> parse(String stdout, String stderr, int exitCode) {
    return const DiskParser().parseDf(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}

class DuProbe extends Probe<List<DuEntry>> {
  const DuProbe(this.path);

  final String path;

  @override
  String command(HostFacts facts) {
    return 'LC_ALL=C du -x -k -d1 ${shellSingleQuote(path)} 2>/dev/null | sort -nr | head -20';
  }

  @override
  List<DuEntry> parse(String stdout, String stderr, int exitCode) {
    return const DiskParser().parseDu(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 45);
}
