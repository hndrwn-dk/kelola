import 'dart:convert';

import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';

/// Parses the single batched HostFacts SSH exec. Pure: fixture-testable.
class HostFactsParser {
  const HostFactsParser();

  HostFacts parse(String stdout) {
    final sections = _sections(stdout);
    final os = sections['OS'] ?? '';
    final init = sections['INIT'] ?? '';
    final pkg = sections['PKG'] ?? '';
    final fw = sections['FW'] ?? '';
    final journal = sections['JOURNAL'] ?? '';
    final arch = (sections['ARCH'] ?? '').trim();
    final runtime = sections['RUNTIME'] ?? '';
    final dmi = _dmiMap(sections['DMI'] ?? '');
    final serialParsed = parseSerial(sections['SERIAL'] ?? '');

    final osId = _osField(os, 'ID') ?? '';
    final osVersionId = _osField(os, 'VERSION_ID') ?? '';
    final pretty = _osField(os, 'PRETTY_NAME');

    final systemdVersion = _systemdVersion(init);
    final initSystem = _initSystem(init, systemdVersion);
    final groups = journal.trim().split(RegExp(r'\s+'));

    return HostFacts(
      osId: osId,
      osVersionId: osVersionId,
      prettyName: pretty,
      init: initSystem,
      systemdVersion: systemdVersion,
      pkg: _packageManager(pkg),
      fw: _firewall(fw),
      hasJournald: initSystem == InitSystem.systemd,
      journalReadable: groups.contains('systemd-journal') ||
          groups.contains('adm'),
      arch: arch,
      runtimes: _runtimes(runtime),
      nprocCores: parseNproc(sections['NPROC'] ?? ''),
      model: parseModel(dmi),
      virt: _nonEmpty(sections['VIRT'] ?? ''),
      biosVendor: _dmiValue(dmi, 'bios_vendor'),
      biosVersion: _dmiValue(dmi, 'bios_version'),
      biosDate: _dmiValue(dmi, 'bios_date'),
      serial: serialParsed.$1,
      serialStatus: serialParsed.$2,
      nics: parseAddr(sections['ADDR'] ?? ''),
      gpu: parseGpu(sections['GPU'] ?? '', sections['NVIDIA'] ?? ''),
    );
  }

  static Map<String, String> _sections(String stdout) {
    final map = <String, String>{};
    final re = RegExp(r'^---([A-Z]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      final name = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      map[name] = stdout.substring(start, end).trim();
    }
    return map;
  }

  static String? _osField(String osRelease, String key) {
    final re = RegExp('^$key=(.*)\$', multiLine: true);
    final m = re.firstMatch(osRelease);
    if (m == null) {
      return null;
    }
    var v = m.group(1)!.trim();
    if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }

  static int? _systemdVersion(String init) {
    final m = RegExp(r'systemd\s+(\d+)').firstMatch(init);
    if (m == null) {
      return null;
    }
    return int.tryParse(m.group(1)!);
  }

  static InitSystem _initSystem(String init, int? systemdVersion) {
    if (systemdVersion != null || init.contains('systemd')) {
      return InitSystem.systemd;
    }
    if (init.contains('rc-service') ||
        init.contains('openrc') ||
        init.contains('openrc-run')) {
      return InitSystem.openrc;
    }
    if (init.contains('init')) {
      return InitSystem.sysvinit;
    }
    return InitSystem.unknown;
  }

  static PackageManager _packageManager(String pkg) {
    if (pkg.contains('apt-get')) {
      return PackageManager.apt;
    }
    if (pkg.contains('dnf')) {
      return PackageManager.dnf;
    }
    if (RegExp(r'(^|/|\\)yum(\s|$)').hasMatch(pkg) || pkg.contains('/yum')) {
      return PackageManager.yum;
    }
    if (pkg.contains('zypper')) {
      return PackageManager.zypper;
    }
    if (pkg.contains('apk')) {
      return PackageManager.apk;
    }
    if (pkg.contains('pacman')) {
      return PackageManager.pacman;
    }
    return PackageManager.unknown;
  }

  static FirewallBackend _firewall(String fw) {
    if (fw.contains('firewall-cmd')) {
      return FirewallBackend.firewalld;
    }
    if (RegExp(r'(^|/|\\)ufw(\s|$)').hasMatch(fw) || fw.contains('/ufw')) {
      return FirewallBackend.ufw;
    }
    if (RegExp(r'(^|/|\\)nft(\s|$)').hasMatch(fw) || fw.contains('/nft')) {
      return FirewallBackend.nftables;
    }
    if (fw.contains('iptables')) {
      return FirewallBackend.iptables;
    }
    return FirewallBackend.none;
  }

  static List<String> _runtimes(String raw) {
    final names = <String>{};
    for (final line in raw.split(RegExp(r'\s+'))) {
      final base = line.split('/').last.trim();
      if (base.isEmpty) {
        continue;
      }
      names.add(base);
    }
    return names.toList();
  }

  /// Whole-line positive integer only. Empty, 0, or garbage → null (unknown).
  static int? parseNproc(String raw) {
    final line = raw.trim();
    if (line.isEmpty) {
      return null;
    }
    final n = int.tryParse(line);
    if (n == null || n <= 0) {
      return null;
    }
    return n;
  }

  static String? parseModel(Map<String, String> dmi) {
    final vendor = _dmiValue(dmi, 'sys_vendor');
    final product = _dmiValue(dmi, 'product_name');
    if (vendor == null && product == null) {
      return null;
    }
    if (vendor == null) {
      return product;
    }
    if (product == null) {
      return vendor;
    }
    return '$vendor $product';
  }

  static (String?, SerialStatus) parseSerial(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (null, SerialStatus.missing);
    }
    final lines = trimmed.split('\n');
    final head = lines.first.trim();
    if (head == 'REQUIRES_ROOT' ||
        head.toLowerCase().contains('password is required') ||
        head.toLowerCase().contains('a terminal is required')) {
      return (null, SerialStatus.requiresRoot);
    }
    var value = head == 'OK' ? lines.skip(1).join('\n').trim() : trimmed;
    value = value.trim();
    if (value.isEmpty || _unusableSerial(value)) {
      return (null, SerialStatus.missing);
    }
    return (value, SerialStatus.available);
  }

  static List<HostNic> parseAddr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) {
        return const [];
      }
      final nics = <HostNic>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final map = item.cast<String, dynamic>();
        final name = (map['ifname'] ?? '').toString().trim();
        final flags = _stringList(map['flags']);
        if (name.isEmpty || name == 'lo' || flags.contains('LOOPBACK')) {
          continue;
        }
        final mac = _usableMac((map['address'] ?? '').toString());
        final infos = map['addr_info'];
        String? ipv4;
        String? ipv6;
        if (infos is List) {
          ipv4 = _pickAddr(infos, 'inet');
          ipv6 = _pickAddr(infos, 'inet6');
        }
        if (mac == null && ipv4 == null && ipv6 == null) {
          continue;
        }
        nics.add(HostNic(name: name, mac: mac, ipv4: ipv4, ipv6: ipv6));
      }
      return nics;
    } on FormatException {
      return const [];
    }
  }

  static HostGpu? parseGpu(String lspci, String nvidia) {
    final lspciLine = lspci
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final nvidiaLine = nvidia
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    String? model;
    String? vram;
    String? driver;
    if (nvidiaLine.isNotEmpty) {
      final parts = nvidiaLine.split(',').map((p) => p.trim()).toList();
      if (parts.length >= 3) {
        driver = parts.last;
        vram = parts[parts.length - 2];
        model = parts.sublist(0, parts.length - 2).join(', ');
      } else {
        model = nvidiaLine;
      }
    }
    if ((model == null || model.isEmpty) && lspciLine.isNotEmpty) {
      model = _lspciModel(lspciLine);
    }
    if (model == null && vram == null && driver == null) {
      return null;
    }
    return HostGpu(model: model, vram: vram, driver: driver);
  }

  static Map<String, String> _dmiMap(String raw) {
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      final key = line.substring(0, idx).trim();
      final value = line.substring(idx + 1).trim();
      if (key.isEmpty || value.isEmpty) {
        continue;
      }
      map[key] = value;
    }
    return map;
  }

  static String? _dmiValue(Map<String, String> dmi, String key) {
    return _nonEmpty(dmi[key] ?? '');
  }

  static String? _nonEmpty(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  static bool _unusableSerial(String value) {
    final lower = value.toLowerCase();
    return lower == 'none' ||
        lower == 'not specified' ||
        lower == 'not available' ||
        lower == 'to be filled by o.e.m.' ||
        lower == 'system serial number' ||
        lower == '0';
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }
    return [
      for (final item in raw) item.toString(),
    ];
  }

  static String? _usableMac(String raw) {
    final mac = raw.trim();
    if (mac.isEmpty) {
      return null;
    }
    final compact = mac.replaceAll(RegExp(r'[:\-]'), '');
    if (compact.replaceAll('0', '').isEmpty) {
      return null;
    }
    return mac;
  }

  static String? _pickAddr(List<dynamic> infos, String family) {
    String? fallback;
    for (final item in infos) {
      if (item is! Map) {
        continue;
      }
      final map = item.cast<String, dynamic>();
      if (map['family']?.toString() != family) {
        continue;
      }
      final local = (map['local'] ?? '').toString().trim();
      if (local.isEmpty) {
        continue;
      }
      final scope = (map['scope'] ?? '').toString();
      if (scope == 'global') {
        return local;
      }
      fallback ??= local;
    }
    return fallback;
  }

  static String _lspciModel(String line) {
    final idx = line.indexOf(': ');
    if (idx >= 0 && idx + 2 < line.length) {
      return line.substring(idx + 2).trim();
    }
    return line;
  }
}
