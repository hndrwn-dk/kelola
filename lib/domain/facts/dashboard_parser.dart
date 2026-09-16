import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/metrics/rate_sample.dart';

class DiskRootReading {
  const DiskRootReading({
    required this.known,
    this.percent,
    this.usedKib = 0,
    this.totalKib = 0,
  });

  final bool known;
  final int? percent;
  final int usedKib;
  final int totalKib;
}

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

    final uptime = parseUptime(sections['UPTIME'] ?? '') ?? Duration.zero;
    final loads = _loads(sections['LOAD'] ?? '');
    final mem = MemBreakdown.fromMeminfo(sections['MEM'] ?? '');
    final disk = parseDiskRoot(sections['DISK'] ?? '');
    final cpu = CpuStatBreakdown.fromStatBlocks(
      sections['STAT1'] ?? '',
      sections['STAT2'] ?? '',
    );
    final names = (sections['FAILED_NAMES'] ?? '')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    var failedCount = int.tryParse((sections['FAILED'] ?? '').trim()) ?? names.length;
    if (failedCount == 0 && names.isNotEmpty) {
      failedCount = names.length;
    }

    final nproc = int.tryParse((sections['NPROC'] ?? '').trim()) ?? 0;

    return DashboardSnapshot(
      uptime: uptime,
      load1: loads.$1,
      load5: loads.$2,
      load15: loads.$3,
      cpuPercent: cpu.busyPercent,
      cpu: cpu,
      memUsedPercent: mem.usedPercent,
      mem: mem,
      diskRootPercent: disk.percent ?? 0,
      diskRootUsedKib: disk.usedKib,
      diskRootTotalKib: disk.totalKib,
      nprocCores: nproc > 0 ? nproc : null,
      failedUnitCount: failedCount,
      failedUnitNames: names,
    );
  }

  /// Null when the section is empty or unparseable — never invent zero uptime.
  static Duration? parseUptime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final first = trimmed.split(RegExp(r'\s+')).first;
    final seconds = double.tryParse(first);
    if (seconds == null) {
      return null;
    }
    return Duration(seconds: seconds.floor());
  }

  /// Unknown when `/` is missing from `df` — never invent 0%.
  static DiskRootReading parseDiskRoot(String df) {
    for (final line in df.split('\n').skip(1)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 7) {
        continue;
      }
      final mounted = cols.last;
      if (mounted != '/') {
        continue;
      }
      final pct = int.tryParse(cols[5].replaceAll('%', ''));
      final total = int.tryParse(cols[2]) ?? 0;
      final used = int.tryParse(cols[3]) ?? 0;
      if (pct == null || total <= 0) {
        return const DiskRootReading(known: false);
      }
      return DiskRootReading(
        known: true,
        percent: pct,
        usedKib: used,
        totalKib: total,
      );
    }
    return const DiskRootReading(known: false);
  }

  static (double, double, double) _loads(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    double at(int i) =>
        i < parts.length ? (double.tryParse(parts[i]) ?? 0) : 0;
    return (at(0), at(1), at(2));
  }
}
