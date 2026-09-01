class DashboardSnapshot {
  const DashboardSnapshot({
    required this.uptime,
    required this.load1,
    required this.memUsedPercent,
    required this.diskRootPercent,
    required this.failedUnitCount,
    required this.failedUnitNames,
  });

  final Duration uptime;
  final double load1;
  final int memUsedPercent;
  final int diskRootPercent;
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
