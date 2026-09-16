/// Shared interval for drill-down rate metrics (disk / network).
/// One place — screens and probes must not invent their own.
const Duration kRateSampleInterval = Duration(seconds: 1);

bool isWholeDiskName(String name) {
  if (name.startsWith('loop') ||
      name.startsWith('ram') ||
      name.startsWith('fd')) {
    return false;
  }
  if (RegExp(r'^nvme\d+n\d+$').hasMatch(name)) {
    return true;
  }
  if (RegExp(r'^(sd|vd|xvd|hd)[a-z]+$').hasMatch(name)) {
    return true;
  }
  if (RegExp(r'^mmcblk\d+$').hasMatch(name)) {
    return true;
  }
  if (RegExp(r'^dm-\d+$').hasMatch(name)) {
    return true;
  }
  return false;
}

class DiskIoCounter {
  const DiskIoCounter({
    required this.name,
    required this.reads,
    required this.readSectors,
    required this.writes,
    required this.writeSectors,
    required this.ioTicksMs,
  });

  final String name;
  final int reads;
  final int readSectors;
  final int writes;
  final int writeSectors;
  final int ioTicksMs;
}

class DiskIoCounters {
  const DiskIoCounters(this.byName);

  final Map<String, DiskIoCounter> byName;

  static DiskIoCounters parse(String raw) {
    final map = <String, DiskIoCounter>{};
    for (final line in raw.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 14) {
        continue;
      }
      final name = parts[2];
      if (!isWholeDiskName(name)) {
        continue;
      }
      map[name] = DiskIoCounter(
        name: name,
        reads: int.tryParse(parts[3]) ?? 0,
        readSectors: int.tryParse(parts[5]) ?? 0,
        writes: int.tryParse(parts[7]) ?? 0,
        writeSectors: int.tryParse(parts[9]) ?? 0,
        ioTicksMs: int.tryParse(parts[12]) ?? 0,
      );
    }
    return DiskIoCounters(map);
  }
}

class DiskIoRate {
  const DiskIoRate({
    required this.name,
    required this.readBytesPerSec,
    required this.writeBytesPerSec,
    required this.readIops,
    required this.writeIops,
    required this.busyPercent,
  });

  final String name;
  final double readBytesPerSec;
  final double writeBytesPerSec;
  final double readIops;
  final double writeIops;
  final double busyPercent;
}

class DiskIoRates {
  static List<DiskIoRate> between(
    DiskIoCounters a,
    DiskIoCounters b,
    Duration elapsed,
  ) {
    final secs = elapsed.inMicroseconds / 1e6;
    if (secs <= 0) {
      return const [];
    }
    final out = <DiskIoRate>[];
    for (final name in b.byName.keys) {
      final x = a.byName[name];
      final y = b.byName[name]!;
      if (x == null) {
        continue;
      }
      final readSectors = (y.readSectors - x.readSectors).clamp(0, 1 << 62);
      final writeSectors = (y.writeSectors - x.writeSectors).clamp(0, 1 << 62);
      final reads = (y.reads - x.reads).clamp(0, 1 << 62);
      final writes = (y.writes - x.writes).clamp(0, 1 << 62);
      final ticks = (y.ioTicksMs - x.ioTicksMs).clamp(0, 1 << 62);
      final busy = ((ticks / (secs * 1000)) * 100).clamp(0, 100);
      out.add(
        DiskIoRate(
          name: name,
          readBytesPerSec: (readSectors * 512) / secs,
          writeBytesPerSec: (writeSectors * 512) / secs,
          readIops: reads / secs,
          writeIops: writes / secs,
          busyPercent: busy.toDouble(),
        ),
      );
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

class NetDevCounter {
  const NetDevCounter({
    required this.name,
    required this.rxBytes,
    required this.rxPackets,
    required this.rxErrors,
    required this.txBytes,
    required this.txPackets,
    required this.txErrors,
  });

  final String name;
  final int rxBytes;
  final int rxPackets;
  final int rxErrors;
  final int txBytes;
  final int txPackets;
  final int txErrors;
}

class NetDevCounters {
  const NetDevCounters(this.byName);

  final Map<String, NetDevCounter> byName;

  static NetDevCounters parse(String raw) {
    final map = <String, NetDevCounter>{};
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.contains(':')) {
        continue;
      }
      final colon = trimmed.indexOf(':');
      final name = trimmed.substring(0, colon).trim();
      if (name.isEmpty || name == 'lo' || name.startsWith('lo:')) {
        continue;
      }
      final fields =
          trimmed.substring(colon + 1).trim().split(RegExp(r'\s+'));
      if (fields.length < 16) {
        continue;
      }
      map[name] = NetDevCounter(
        name: name,
        rxBytes: int.tryParse(fields[0]) ?? 0,
        rxPackets: int.tryParse(fields[1]) ?? 0,
        rxErrors: int.tryParse(fields[2]) ?? 0,
        txBytes: int.tryParse(fields[8]) ?? 0,
        txPackets: int.tryParse(fields[9]) ?? 0,
        txErrors: int.tryParse(fields[10]) ?? 0,
      );
    }
    return NetDevCounters(map);
  }
}

class NetDevRate {
  const NetDevRate({
    required this.name,
    required this.rxBytesPerSec,
    required this.txBytesPerSec,
    required this.rxPacketsPerSec,
    required this.txPacketsPerSec,
    required this.rxErrors,
    required this.txErrors,
  });

  final String name;
  final double rxBytesPerSec;
  final double txBytesPerSec;
  final double rxPacketsPerSec;
  final double txPacketsPerSec;
  final int rxErrors;
  final int txErrors;
}

class NetDevRates {
  static List<NetDevRate> between(
    NetDevCounters a,
    NetDevCounters b,
    Duration elapsed,
  ) {
    final secs = elapsed.inMicroseconds / 1e6;
    if (secs <= 0) {
      return const [];
    }
    final out = <NetDevRate>[];
    for (final name in b.byName.keys) {
      final x = a.byName[name];
      final y = b.byName[name]!;
      if (x == null) {
        continue;
      }
      out.add(
        NetDevRate(
          name: name,
          rxBytesPerSec: ((y.rxBytes - x.rxBytes).clamp(0, 1 << 62)) / secs,
          txBytesPerSec: ((y.txBytes - x.txBytes).clamp(0, 1 << 62)) / secs,
          rxPacketsPerSec:
              ((y.rxPackets - x.rxPackets).clamp(0, 1 << 62)) / secs,
          txPacketsPerSec:
              ((y.txPackets - x.txPackets).clamp(0, 1 << 62)) / secs,
          rxErrors: y.rxErrors,
          txErrors: y.txErrors,
        ),
      );
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

class SsSummary {
  const SsSummary({
    required this.total,
    required this.tcp,
    required this.udp,
    required this.estab,
    required this.timewait,
  });

  final int total;
  final int tcp;
  final int udp;
  final int estab;
  final int timewait;

  static SsSummary parse(String raw) {
    var total = 0;
    var tcp = 0;
    var udp = 0;
    var estab = 0;
    var timewait = 0;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      final totalM = RegExp(r'^Total:\s+(\d+)').firstMatch(t);
      if (totalM != null) {
        total = int.tryParse(totalM.group(1)!) ?? 0;
      }
      final tcpM = RegExp(
        r'^TCP:\s+(\d+)\s+\(estab\s+(\d+).*timewait\s+(\d+)',
      ).firstMatch(t);
      if (tcpM != null) {
        tcp = int.tryParse(tcpM.group(1)!) ?? 0;
        estab = int.tryParse(tcpM.group(2)!) ?? 0;
        timewait = int.tryParse(tcpM.group(3)!) ?? 0;
      }
      final udpM = RegExp(r'^UDP\s+(\d+)').firstMatch(t);
      if (udpM != null) {
        udp = int.tryParse(udpM.group(1)!) ?? 0;
      }
    }
    return SsSummary(
      total: total,
      tcp: tcp,
      udp: udp,
      estab: estab,
      timewait: timewait,
    );
  }
}

String formatRateBytes(double bytesPerSec) {
  if (bytesPerSec < 1024) {
    return '${bytesPerSec.round()} B/s';
  }
  final kib = bytesPerSec / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KiB/s';
  }
  final mib = kib / 1024;
  if (mib < 1024) {
    return '${mib.toStringAsFixed(1)} MiB/s';
  }
  return '${(mib / 1024).toStringAsFixed(2)} GiB/s';
}

String formatRateIops(double iops) {
  if (iops >= 100) {
    return '${iops.round()}/s';
  }
  return '${iops.toStringAsFixed(1)}/s';
}

/// Counters from one `/proc/stat` aggregate `cpu ` line.
class CpuStatCounters {
  const CpuStatCounters({
    required this.user,
    required this.nice,
    required this.system,
    required this.idle,
    required this.iowait,
    required this.irq,
    required this.softirq,
    required this.steal,
  });

  final double user;
  final double nice;
  final double system;
  final double idle;
  final double iowait;
  final double irq;
  final double softirq;
  final double steal;

  double get total =>
      user + nice + system + idle + iowait + irq + softirq + steal;

  static CpuStatCounters? parse(String block) {
    final line = block
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    if (line.isEmpty) {
      return null;
    }
    final parts = line.split(RegExp(r'\s+')).skip(1).toList();
    if (parts.length < 5) {
      return null;
    }
    double at(int i) =>
        i < parts.length ? (double.tryParse(parts[i]) ?? 0) : 0;
    return CpuStatCounters(
      user: at(0),
      nice: at(1),
      system: at(2),
      idle: at(3),
      iowait: at(4),
      irq: at(5),
      softirq: at(6),
      steal: at(7),
    );
  }
}

class CpuStatBreakdown {
  const CpuStatBreakdown({
    required this.userPercent,
    required this.systemPercent,
    required this.iowaitPercent,
    required this.busyPercent,
  });

  static const empty = CpuStatBreakdown(
    userPercent: 0,
    systemPercent: 0,
    iowaitPercent: 0,
    busyPercent: 0,
  );

  final double userPercent;
  final double systemPercent;
  final double iowaitPercent;
  final double busyPercent;

  static CpuStatBreakdown between(CpuStatCounters? a, CpuStatCounters? b) {
    if (a == null || b == null) {
      return empty;
    }
    final total = b.total - a.total;
    if (total <= 0) {
      return empty;
    }
    double pct(double delta) => ((delta / total) * 100).clamp(0, 100);
    final user = pct((b.user + b.nice) - (a.user + a.nice));
    final system =
        pct((b.system + b.irq + b.softirq) - (a.system + a.irq + a.softirq));
    final iowait = pct(b.iowait - a.iowait);
    final busy = (user + system + iowait).clamp(0.0, 100.0).toDouble();
    return CpuStatBreakdown(
      userPercent: user,
      systemPercent: system,
      iowaitPercent: iowait,
      busyPercent: busy,
    );
  }

  static CpuStatBreakdown fromStatBlocks(String a, String b) {
    return between(CpuStatCounters.parse(a), CpuStatCounters.parse(b));
  }
}

