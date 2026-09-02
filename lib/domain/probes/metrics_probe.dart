import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class MetricsSnapshot {
  const MetricsSnapshot({
    required this.cpuPercent,
    required this.load1,
    required this.memUsedPercent,
    required this.topCpu,
    required this.topMem,
  });

  final double cpuPercent;
  final double load1;
  final int memUsedPercent;
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
    final mem = _section(stdout, 'MEM');
    return MetricsSnapshot(
      cpuPercent: cpuFromStat(stat1, stat2),
      load1: double.tryParse(load.isEmpty ? '' : load.first) ?? 0,
      memUsedPercent: _memPercent(mem),
      topCpu: _procs(_section(stdout, 'TOPCPU')),
      topMem: _procs(_section(stdout, 'TOPMEM')),
    );
  }

  static double cpuFromStat(String a, String b) {
    final x = _cpuTimes(a);
    final y = _cpuTimes(b);
    if (x == null || y == null) {
      return 0;
    }
    final idle = y.idle - x.idle;
    final total = y.total - x.total;
    if (total <= 0) {
      return 0;
    }
    final busy = (1 - idle / total) * 100;
    if (busy < 0) {
      return 0;
    }
    if (busy > 100) {
      return 100;
    }
    return busy;
  }

  static ({double idle, double total})? _cpuTimes(String block) {
    final line = block
        .split('\n')
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) {
      return null;
    }
    final parts = line.split(RegExp(r'\s+')).skip(1).toList();
    if (parts.length < 5) {
      return null;
    }
    final nums = parts.map((e) => double.tryParse(e) ?? 0).toList();
    final idle = nums[3] + (nums.length > 4 ? nums[4] : 0);
    final total = nums.fold<double>(0, (a, b) => a + b);
    return (idle: idle, total: total);
  }

  static int _memPercent(String meminfo) {
    int? kb(String key) {
      final m = RegExp('^$key:\\s+(\\d+)', multiLine: true).firstMatch(meminfo);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    final total = kb('MemTotal');
    final avail = kb('MemAvailable') ?? kb('MemFree');
    if (total == null || total == 0 || avail == null) {
      return 0;
    }
    return (((total - avail) / total) * 100).round().clamp(0, 100);
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
      out.add(
        MetricsProc(
          pid: int.tryParse(m.group(1)!) ?? 0,
          user: m.group(2)!,
          cpu: double.tryParse(m.group(3)!) ?? 0,
          mem: double.tryParse(m.group(4)!) ?? 0,
          rssKb: int.tryParse(m.group(5)!) ?? 0,
          command: m.group(6)!.trim(),
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
