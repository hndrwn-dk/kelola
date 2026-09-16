import 'package:kelola/domain/metrics/rate_sample.dart';

class MemBreakdown {
  const MemBreakdown({
    required this.totalKb,
    required this.availableKb,
    required this.freeKb,
    required this.cachedKb,
    required this.buffersKb,
    required this.swapTotalKb,
    required this.swapFreeKb,
  });

  static const empty = MemBreakdown(
    totalKb: 0,
    availableKb: 0,
    freeKb: 0,
    cachedKb: 0,
    buffersKb: 0,
    swapTotalKb: 0,
    swapFreeKb: 0,
  );

  factory MemBreakdown.fromMeminfo(String meminfo) {
    int? total;
    int? available;
    int? free;
    int? cached;
    int? buffers;
    int? swapTotal;
    int? swapFree;
    for (final line in meminfo.split('\n')) {
      if (line.startsWith('MemTotal:')) {
        total = _kib(line);
      } else if (line.startsWith('MemAvailable:')) {
        available = _kib(line);
      } else if (line.startsWith('MemFree:')) {
        free = _kib(line);
      } else if (line.startsWith('Cached:')) {
        cached = _kib(line);
      } else if (line.startsWith('Buffers:')) {
        buffers = _kib(line);
      } else if (line.startsWith('SwapTotal:')) {
        swapTotal = _kib(line);
      } else if (line.startsWith('SwapFree:')) {
        swapFree = _kib(line);
      }
    }
    return MemBreakdown(
      totalKb: total ?? 0,
      availableKb: available ?? free ?? 0,
      freeKb: free ?? 0,
      cachedKb: cached ?? 0,
      buffersKb: buffers ?? 0,
      swapTotalKb: swapTotal ?? 0,
      swapFreeKb: swapFree ?? 0,
    );
  }

  static int _kib(String line) {
    final m = RegExp(r'(\d+)').firstMatch(line);
    return int.tryParse(m?.group(1) ?? '0') ?? 0;
  }

  final int totalKb;
  final int availableKb;
  final int freeKb;
  final int cachedKb;
  final int buffersKb;
  final int swapTotalKb;
  final int swapFreeKb;

  /// Used excluding reclaimable cache/buffers (total − MemAvailable).
  int get usedKb => (totalKb - availableKb).clamp(0, totalKb);

  int get swapUsedKb => (swapTotalKb - swapFreeKb).clamp(0, swapTotalKb);

  bool get hasSwap => swapTotalKb > 0;

  /// Swap that is actually consuming space — hide zero-used swap on cards.
  bool get swapInUse => swapUsedKb > 0;

  int get usedPercent {
    if (totalKb <= 0) {
      return 0;
    }
    return ((usedKb / totalKb) * 100).round().clamp(0, 100);
  }

  /// Single-bar fill for dashboard StatCard (MemAvailable-based used %).
  double get meterFraction => usedPercent / 100;

  /// Stacked-meter fractions of MemTotal (used / cached+buffers / free).
  double get meterUsed => totalKb <= 0 ? 0 : usedKb / totalKb;

  double get meterCached {
    if (totalKb <= 0) {
      return 0;
    }
    return ((cachedKb + buffersKb) / totalKb).clamp(0.0, 1.0);
  }

  double get meterFree {
    if (totalKb <= 0) {
      return 0;
    }
    return (freeKb / totalKb).clamp(0.0, 1.0);
  }

  /// Compact kibibyte label for memory detail rows.
  static String formatKiB(int kib) {
    if (kib < 1024) {
      return '${kib}K';
    }
    final mib = kib / 1024;
    if (mib < 1024) {
      return mib >= 10 ? '${mib.round()}M' : '${mib.toStringAsFixed(1)}M';
    }
    final gib = mib / 1024;
    return gib >= 10 ? '${gib.round()}G' : '${gib.toStringAsFixed(1)}G';
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.uptime,
    required this.load1,
    this.load5 = 0,
    this.load15 = 0,
    required this.cpuPercent,
    this.cpu = CpuStatBreakdown.empty,
    required this.memUsedPercent,
    this.mem = MemBreakdown.empty,
    required this.diskRootPercent,
    this.diskRootUsedKib = 0,
    this.diskRootTotalKib = 0,
    this.nprocCores,
    required this.failedUnitCount,
    required this.failedUnitNames,
  });

  final Duration uptime;
  final double load1;
  final double load5;
  final double load15;
  final double cpuPercent;
  final CpuStatBreakdown cpu;
  final int memUsedPercent;
  final MemBreakdown mem;
  final int diskRootPercent;
  final int diskRootUsedKib;
  final int diskRootTotalKib;
  /// Online CPU count from `nproc` in the dashboard batch (card denominator).
  final int? nprocCores;
  final int failedUnitCount;
  final List<String> failedUnitNames;

  HostAttentionFromSnapshot get attention {
    if (failedUnitCount > 0) {
      return HostAttentionFromSnapshot.failedUnits;
    }
    if (diskRootPercent >= 90) {
      return HostAttentionFromSnapshot.diskHigh;
    }
    return HostAttentionFromSnapshot.healthy;
  }
}

enum HostAttentionFromSnapshot { failedUnits, diskHigh, healthy }
