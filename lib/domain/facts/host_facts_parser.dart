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
      nprocCores: _nproc(sections['NPROC'] ?? ''),
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

  static int? _nproc(String raw) {
    final n = int.tryParse(raw.trim().split(RegExp(r'\s+')).first);
    if (n == null || n <= 0) {
      return null;
    }
    return n;
  }
}
