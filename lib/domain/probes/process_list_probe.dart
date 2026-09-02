import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ProcessListProbe extends Probe<List<ProcessRow>> {
  const ProcessListProbe();

  @override
  String get auditTitle => 'Listed processes';

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
ps -eo pid,ppid,user,pcpu,pmem,rss,etime,stat,comm --no-headers --sort=-pcpu
''';
  }

  @override
  List<ProcessRow> parse(String stdout, String stderr, int exitCode) {
    return const ProcessListParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 15);
}
