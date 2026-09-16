import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class DiskstatsProbe extends Probe<DiskIoCounters> {
  const DiskstatsProbe();

  @override
  String get auditTitle => 'Sampled diskstats';

  @override
  String command(HostFacts facts) => 'LC_ALL=C cat /proc/diskstats';

  @override
  DiskIoCounters parse(String stdout, String stderr, int exitCode) {
    return DiskIoCounters.parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 8);
}

class NetDevProbe extends Probe<NetDevCounters> {
  const NetDevProbe();

  @override
  String get auditTitle => 'Sampled netdev';

  @override
  String command(HostFacts facts) => 'LC_ALL=C cat /proc/net/dev';

  @override
  NetDevCounters parse(String stdout, String stderr, int exitCode) {
    return NetDevCounters.parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 8);
}

class SsSummaryProbe extends Probe<SsSummary> {
  const SsSummaryProbe();

  @override
  String get auditTitle => 'Sampled ss summary';

  @override
  String command(HostFacts facts) => 'LC_ALL=C ss -s 2>/dev/null || true';

  @override
  SsSummary parse(String stdout, String stderr, int exitCode) {
    return SsSummary.parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 8);
}
