import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class MetricsSnapshot {
  const MetricsSnapshot({
    required this.cpuPercent,
    this.cpu = CpuStatBreakdown.empty,
    required this.load1,
    required this.memUsedPercent,
    this.mem = MemBreakdown.empty,
    required this.topCpu,
    required this.topMem,
  });

  final double cpuPercent;
  final CpuStatBreakdown cpu;
  final double load1;
  final int memUsedPercent;
  final MemBreakdown mem;
  final List<MetricsProc> topCpu;
  final List<MetricsProc> topMem;
}

class MetricsProc {
  const MetricsProc({
    required this.pid,
    required this.user,
    required this.cpu,
    required this.mem,
    required this.rssKb,
    required this.command,
  });

  final int pid;
  final String user;
  final double cpu;
  final double mem;
  final int rssKb;
  final String command;
}

class MetricsParser {
  const MetricsParser();

  MetricsSnapshot parse(String stdout) {
    final stat1 = _section(stdout, 'STAT1');
    final stat2 = _section(stdout, 'STAT2');
    final load = _section(stdout, 'LOAD').trim().split(RegExp(r'\s+'));
    final mem = MemBreakdown.fromMeminfo(_section(stdout, 'MEM'));
    final cpu = CpuStatBreakdown.fromStatBlocks(stat1, stat2);
    return MetricsSnapshot(
      cpuPercent: cpu.busyPercent,
      cpu: cpu,
      load1: double.tryParse(load.isEmpty ? '' : load.first) ?? 0,
      memUsedPercent: mem.usedPercent,
      mem: mem,
      topCpu: _procs(_section(stdout, 'TOPCPU')),
      topMem: _procs(_section(stdout, 'TOPMEM')),
    );
  }

  static double cpuFromStat(String a, String b) {
    return CpuStatBreakdown.fromStatBlocks(a, b).busyPercent;
  }

  static List<MetricsProc> _procs(String raw) {
    final out = <MetricsProc>[];
    final re = RegExp(
      r'^\s*(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s+(.*)$',
    );
    for (final line in raw.split('\n')) {
      final m = re.firstMatch(line);
      if (m == null) {
        continue;
      }
      final command = m.group(6)!.trim();
      // MetricsProbe shells out to `ps`; exclude that self-sample noise.
      if (command == 'ps' || command.endsWith('/ps')) {
        continue;
      }
      out.add(
        MetricsProc(
          pid: int.tryParse(m.group(1)!) ?? 0,
          user: m.group(2)!,
          cpu: double.tryParse(m.group(3)!) ?? 0,
          mem: double.tryParse(m.group(4)!) ?? 0,
          rssKb: int.tryParse(m.group(5)!) ?? 0,
          command: command,
        ),
      );
    }
    return out;
  }

  static String _section(String stdout, String name) {
    final re = RegExp(r'^---([A-Z0-9_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      if (matches[i].group(1) != name) {
        continue;
      }
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      return stdout.substring(start, end).replaceAll('\r', '').trim();
    }
    return '';
  }
}

class MetricsProbe extends Probe<MetricsSnapshot> {
  const MetricsProbe();

  @override
  String get auditTitle => 'Polled metrics';

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
echo "---STAT1---"
head -1 /proc/stat
echo "---LOAD---"
cat /proc/loadavg
echo "---MEM---"
cat /proc/meminfo
echo "---TOPCPU---"
ps -eo pid,user,pcpu,pmem,rss,comm --no-headers --sort=-pcpu | head -12
echo "---TOPMEM---"
ps -eo pid,user,pcpu,pmem,rss,comm --no-headers --sort=-pmem | head -12
sleep 0.35
echo "---STAT2---"
head -1 /proc/stat
''';
  }

  @override
  MetricsSnapshot parse(String stdout, String stderr, int exitCode) {
    return const MetricsParser().parse(stdout);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 12);
}

class CpuTickProbe extends Probe<double> {
  const CpuTickProbe();

  @override
  String get auditTitle => 'Polled CPU';

  @override
  String command(HostFacts facts) {
    return r'''
LC_ALL=C
echo "---STAT1---"
head -1 /proc/stat
sleep 0.35
echo "---STAT2---"
head -1 /proc/stat
''';
  }

  @override
  double parse(String stdout, String stderr, int exitCode) {
    return MetricsParser.cpuFromStat(
      MetricsParser._section(stdout, 'STAT1'),
      MetricsParser._section(stdout, 'STAT2'),
    );
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 8);
}
