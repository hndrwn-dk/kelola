class DiskMount {
  const DiskMount({
    required this.device,
    required this.fsType,
    required this.kibTotal,
    required this.kibUsed,
    required this.usedPercent,
    required this.mounted,
  });

  final String device;
  final String fsType;
  final int kibTotal;
  final int kibUsed;
  final int usedPercent;
  final String mounted;
}

bool isEphemeralMount(DiskMount m) {
  const types = {
    'tmpfs',
    'devtmpfs',
    'ramfs',
    'overlay',
    'squashfs',
    'proc',
    'sysfs',
    'cgroup',
    'cgroup2',
    'devpts',
    'securityfs',
    'pstore',
    'bpf',
    'tracefs',
    'debugfs',
    'configfs',
    'fusectl',
    'mqueue',
    'hugetlbfs',
    'autofs',
    'efivarfs',
  };
  if (types.contains(m.fsType.toLowerCase())) {
    return true;
  }
  final p = m.mounted;
  return p.startsWith('/run/') ||
      p.startsWith('/dev/') ||
      p.startsWith('/sys/') ||
      p.startsWith('/proc/') ||
      p == '/dev' ||
      p == '/run' ||
      p == '/sys' ||
      p == '/proc';
}

class DiskGroups {
  const DiskGroups({required this.primary, required this.ephemeral});

  final List<DiskMount> primary;
  final List<DiskMount> ephemeral;
}

DiskGroups groupDiskMounts(List<DiskMount> mounts) {
  final primary = <DiskMount>[];
  final ephemeral = <DiskMount>[];
  for (final m in mounts) {
    if (isEphemeralMount(m)) {
      ephemeral.add(m);
    } else {
      primary.add(m);
    }
  }
  int rank(DiskMount m) {
    if (m.mounted == '/') {
      return 0;
    }
    return 1;
  }

  primary.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) {
      return r;
    }
    return b.usedPercent.compareTo(a.usedPercent);
  });
  ephemeral.sort((a, b) => b.usedPercent.compareTo(a.usedPercent));
  return DiskGroups(primary: primary, ephemeral: ephemeral);
}

class DuEntry {
  const DuEntry({required this.kib, required this.path});

  final int kib;
  final String path;
}

class DiskParser {
  const DiskParser();

  List<DiskMount> parseDf(String stdout) {
    final out = <DiskMount>[];
    for (final line in stdout.split('\n').skip(1)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 7 || cols.last == 'on') {
        continue;
      }
      final pct = int.tryParse(cols[5].replaceAll('%', '')) ?? 0;
      out.add(
        DiskMount(
          device: cols[0],
          fsType: cols[1],
          kibTotal: int.tryParse(cols[2]) ?? 0,
          kibUsed: int.tryParse(cols[3]) ?? 0,
          usedPercent: pct,
          mounted: cols.last,
        ),
      );
    }
    out.sort((a, b) => b.usedPercent.compareTo(a.usedPercent));
    return out;
  }

  List<DuEntry> parseDu(String stdout) {
    final out = <DuEntry>[];
    for (final line in stdout.split('\n')) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 2) {
        continue;
      }
      final kib = int.tryParse(cols.first);
      if (kib == null) {
        continue;
      }
      out.add(DuEntry(kib: kib, path: cols.sublist(1).join(' ')));
    }
    return out;
  }
}
