import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';

class PackageParser {
  const PackageParser();

  PackageSnapshot parse({
    required PackageManager manager,
    required String stdout,
    String stderr = '',
    int exitCode = 0,
  }) {
    final updatesBlock = _section(stdout, 'UPDATES');
    final securityBlock = _section(stdout, 'SECURITY');
    final rebootBlock = _section(stdout, 'REBOOT');

    var updates = _parseUpdates(manager, updatesBlock);
    final securityNames = {
      for (final u in _parseUpdates(manager, securityBlock)) u.name,
      for (final u in updates)
        if (u.security) u.name,
    };
    updates = [
      for (final u in updates)
        u.copyWith(security: u.security || securityNames.contains(u.name)),
    ];
    if (updates.isEmpty && securityNames.isNotEmpty) {
      updates = _parseUpdates(manager, securityBlock);
    }

    final reboot = _parseReboot(rebootBlock);
    return PackageSnapshot(
      manager: manager,
      updates: updates,
      rebootRequired: reboot.required,
      rebootReasons: reboot.reasons,
    );
  }

  List<PackageUpdate> _parseUpdates(PackageManager manager, String block) {
    return switch (manager) {
      PackageManager.apt => _parseApt(block),
      PackageManager.dnf => _parseDnf(block),
      PackageManager.yum => _parseDnf(block),
      PackageManager.zypper => _parseZypper(block),
      PackageManager.apk => _parseApk(block),
      PackageManager.pacman => _parsePacman(block),
      PackageManager.unknown => const [],
    };
  }

  List<PackageUpdate> _parseApt(String block) {
    final out = <PackageUpdate>[];
    final seen = <String>{};
    final inst = RegExp(
      r'^Inst (\S+)(?: \[([^\]]*)\])? \(([^)\s]+)([^)]*)\)',
    );
    for (final line in block.split('\n')) {
      final m = inst.firstMatch(line);
      if (m == null) {
        continue;
      }
      final name = m.group(1)!;
      if (!seen.add(name)) {
        continue;
      }
      final rest = m.group(4) ?? '';
      final security = rest.toLowerCase().contains('security');
      out.add(
        PackageUpdate(
          name: name,
          currentVersion: _emptyToNull(m.group(2)),
          candidateVersion: m.group(3),
          security: security,
        ),
      );
    }
    return out;
  }

  List<PackageUpdate> _parseDnf(String block) {
    final out = <PackageUpdate>[];
    final seen = <String>{};
    var skip = false;
    final nevra = RegExp(
      r'^(\S+)\s+(\S+)\s+(\S+)\s*$',
    );
    final updateinfo = RegExp(
      r'(?:Sec\.?|security)\s+(\S+)$',
      caseSensitive: false,
    );
    for (final raw in block.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.startsWith('obsoleting') ||
          lower.startsWith('obsoleted')) {
        skip = true;
        continue;
      }
      if (skip) {
        continue;
      }
      if (lower.startsWith('last metadata') ||
          lower.startsWith('security:') ||
          lower.startsWith('fedora') ||
          lower.startsWith('extra packages') ||
          lower == 'n/a') {
        continue;
      }
      final info = updateinfo.firstMatch(line);
      if (info != null) {
        final nevraName = _nameFromNevra(info.group(1)!);
        if (seen.add(nevraName)) {
          out.add(PackageUpdate(name: nevraName, security: true));
        }
        continue;
      }
      final m = nevra.firstMatch(line);
      if (m == null) {
        continue;
      }
      final nameArch = m.group(1)!;
      if (nameArch.contains('====') || nameArch.startsWith('Loaded')) {
        continue;
      }
      final name = nameArch.contains('.')
          ? nameArch.substring(0, nameArch.lastIndexOf('.'))
          : nameArch;
      if (!seen.add(name)) {
        continue;
      }
      final repo = m.group(3)!.toLowerCase();
      out.add(
        PackageUpdate(
          name: name,
          candidateVersion: m.group(2),
          security: repo.contains('security') || repo.contains('updates-security'),
        ),
      );
    }
    return out;
  }

  List<PackageUpdate> _parseZypper(String block) {
    final out = <PackageUpdate>[];
    final seen = <String>{};
    for (final raw in block.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('S ') ||
          line.startsWith('--') ||
          line.toLowerCase().startsWith('no updates') ||
          line.toLowerCase() == 'n/a') {
        continue;
      }
      if (!line.contains('|')) {
        continue;
      }
      final cols = line.split('|').map((c) => c.trim()).toList();
      if (cols.length < 4) {
        continue;
      }
      final name = cols.length >= 6 ? cols[2] : cols[1];
      if (name.isEmpty || name.toLowerCase() == 'name') {
        continue;
      }
      if (!seen.add(name)) {
        continue;
      }
      final current = cols.length >= 6 ? cols[3] : null;
      final available = cols.length >= 6 ? cols[4] : cols[2];
      out.add(
        PackageUpdate(
          name: name,
          currentVersion: current,
          candidateVersion: available,
        ),
      );
    }
    return out;
  }

  List<PackageUpdate> _parseApk(String block) {
    final out = <PackageUpdate>[];
    final seen = <String>{};
    final re = RegExp(r'^(.+)-([0-9]\S*) < (\S+)\s*$');
    for (final raw in block.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.toLowerCase() == 'n/a') {
        continue;
      }
      final m = re.firstMatch(line);
      if (m != null) {
        final name = m.group(1)!;
        if (!seen.add(name)) {
          continue;
        }
        out.add(
          PackageUpdate(
            name: name,
            currentVersion: m.group(2),
            candidateVersion: m.group(3),
          ),
        );
        continue;
      }
      final lt = line.indexOf(' < ');
      if (lt <= 0) {
        continue;
      }
      final left = line.substring(0, lt).trim();
      final right = line.substring(lt + 3).trim();
      final dash = left.lastIndexOf('-');
      final name = dash > 0 ? left.substring(0, dash) : left;
      final current = dash > 0 ? left.substring(dash + 1) : null;
      if (!seen.add(name)) {
        continue;
      }
      out.add(
        PackageUpdate(
          name: name,
          currentVersion: current,
          candidateVersion: right,
        ),
      );
    }
    return out;
  }

  List<PackageUpdate> _parsePacman(String block) {
    final out = <PackageUpdate>[];
    final seen = <String>{};
    final re = RegExp(r'^(\S+)\s+(\S+)\s+->\s+(\S+)');
    for (final raw in block.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.toLowerCase() == 'n/a') {
        continue;
      }
      final m = re.firstMatch(line);
      if (m == null) {
        continue;
      }
      final name = m.group(1)!;
      if (!seen.add(name)) {
        continue;
      }
      out.add(
        PackageUpdate(
          name: name,
          currentVersion: m.group(2),
          candidateVersion: m.group(3),
        ),
      );
    }
    return out;
  }

  ({bool required, List<String> reasons}) _parseReboot(String block) {
    var required = false;
    final reasons = <String>[];
    for (final raw in block.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line == 'FILE' ||
          line == 'REBOOT_REQUIRED' ||
          line == 'NEEDS_RESTARTING_R:1') {
        required = true;
        continue;
      }
      if (line.startsWith('NEEDS_RESTARTING_R:')) {
        continue;
      }
      if (line.toLowerCase().contains('reboot is required') ||
          line.toLowerCase().contains('rebooting is required')) {
        required = true;
        continue;
      }
      reasons.add(line);
    }
    if (reasons.isNotEmpty && block.contains('FILE')) {
      required = true;
    }
    return (required: required, reasons: reasons);
  }

  static String _section(String stdout, String name) {
    final marker = '---$name---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      if (name == 'UPDATES' && !_hasKelolaSections(stdout)) {
        return stdout;
      }
      return '';
    }
    final start = i + marker.length;
    final next = stdout.indexOf('\n---', start);
    if (next < 0) {
      return stdout.substring(start);
    }
    return stdout.substring(start, next);
  }

  static bool _hasKelolaSections(String stdout) {
    return stdout.contains('---UPDATES---') ||
        stdout.contains('---PKG---') ||
        stdout.contains('---SECURITY---') ||
        stdout.contains('---REBOOT---');
  }

  static String? _emptyToNull(String? v) {
    if (v == null || v.isEmpty) {
      return null;
    }
    return v;
  }

  static String _nameFromNevra(String nevra) {
    var s = nevra;
    final archDot = s.lastIndexOf('.');
    if (archDot > 0) {
      s = s.substring(0, archDot);
    }
    final lastDash = s.lastIndexOf('-');
    if (lastDash > 0) {
      final prev = s.lastIndexOf('-', lastDash - 1);
      if (prev > 0) {
        return s.substring(0, prev);
      }
      return s.substring(0, lastDash);
    }
    return s;
  }
}
