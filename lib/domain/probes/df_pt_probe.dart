import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// Raw `df -PT` for the diagnostic pack. Disk UI still uses [DiskProbe].
class DfPtProbe extends Probe<String> {
  const DfPtProbe();

  @override
  String get auditTitle => 'Read df -PT';

  @override
  String command(HostFacts facts) => 'LC_ALL=C df -PT';

  @override
  String parse(String stdout, String stderr, int exitCode) => stdout;

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;
}
