import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/probes/metrics_probe.dart';

class DashboardParser {
  const DashboardParser();

  DashboardSnapshot parse(String stdout) {
    final sections = <String, String>{};
    final re = RegExp(r'^---([A-Z0-9_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      final name = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      sections[name] = stdout.substring(start, end).trim();
    }

    final uptime = _uptime(sections['UPTIME'] ?? '');
    final load1 = _load1(sections['LOAD'] ?? '');
    final mem = _memPercent(sections['MEM'] ?? '');
    final disk = _diskRootPercent(sections['DISK'] ?? '');
    final names = (sections['FAILED_NAMES'] ?? '')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    var failedCount = int.tryParse((sections['FAILED'] ?? '').trim()) ?? names.length;
    if (failedCount == 0 && names.isNotEmpty) {
      failedCount = names.length;
    }

    return DashboardSnapshot(
      uptime: uptime,
      load1: load1,
      cpuPercent: MetricsParser.cpuFromStat(
        sections['STAT1'] ?? '',
        sections['STAT2'] ?? '',
      ),
      memUsedPercent: mem,
      diskRootPercent: disk,
      failedUnitCount: failedCount,
      failedUnitNames: names,
    );
  }

  static Duration _uptime(String raw) {
    final first = raw.trim().split(RegExp(r'\s+')).first;
    final seconds = double.tryParse(first) ?? 0;
    return Duration(seconds: seconds.floor());
  }

  static double _load1(String raw) {
    final first = raw.trim().split(RegExp(r'\s+')).first;
    return double.tryParse(first) ?? 0;
  }

  static int _memPercent(String meminfo) {
    int? total;
    int? available;
    for (final line in meminfo.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        total = _kib(line);
      } else if (line.startsWith('MemAvailable:')) {
        available = _kib(line);
      }
    }
    if (total == null || total == 0 || available == null) {
      return 0;
    }
    final used = total - available;
    return ((used / total) * 100).round().clamp(0, 100);
  }

  static int _kib(String line) {
    final m = RegExp(r'(\d+)').firstMatch(line);
    return int.tryParse(m?.group(1) ?? '0') ?? 0;
  }

  static int _diskRootPercent(String df) {
    for (final line in df.split('\n').skip(1)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 7) {
        continue;
      }
      final mounted = cols.last;
      if (mounted != '/') {
        continue;
      }
      final pct = cols[5].replaceAll('%', '');
      return int.tryParse(pct) ?? 0;
    }
    return 0;
  }
}
