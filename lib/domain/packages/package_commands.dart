import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Command table from M6. Manager comes from [HostFacts.pkg] — never `command -v`.
class PackageCommands {
  const PackageCommands();

  static bool securitySupported(PackageManager pkg) {
    switch (pkg) {
      case PackageManager.apt:
      case PackageManager.dnf:
      case PackageManager.yum:
      case PackageManager.zypper:
        return true;
      case PackageManager.apk:
      case PackageManager.pacman:
      case PackageManager.unknown:
        return false;
    }
  }

  static String listUpdates(PackageManager pkg) {
    return switch (pkg) {
      PackageManager.apt => 'apt-get -s upgrade',
      PackageManager.dnf => _checkUpdateRefresh('dnf'),
      PackageManager.yum => _checkUpdateRefresh('yum'),
      PackageManager.zypper => 'zypper -q lu',
      PackageManager.apk => "apk version -l '<'",
      PackageManager.pacman =>
        'if command -v checkupdates >/dev/null 2>&1; then checkupdates; else pacman -Qu; fi',
      PackageManager.unknown => 'echo unsupported; exit 1',
    };
  }

  /// Same command as an interactive `sudo dnf check-update --refresh`, with
  /// stdin closed so it cannot wait on a TTY. No unprivileged dnf fallback:
  /// that hung on Rocky while the VM command (root, TTY) finished quickly.
  static String _checkUpdateRefresh(String bin) {
    return '/usr/bin/timeout -k 5 60 sudo -n /usr/bin/$bin --color=never '
        'check-update --refresh </dev/null';
  }

  /// Fleet tile batch — never `--refresh`. Metadata refresh made Rocky hosts
  /// exceed the fleet timeout and look unreachable while SSH stayed up.
  static String listUpdatesForFleet(PackageManager pkg) {
    return switch (pkg) {
      PackageManager.dnf => 'dnf check-update',
      PackageManager.yum => 'yum check-update',
      _ => listUpdates(pkg),
    };
  }

  static String listSecurity(PackageManager pkg) {
    return switch (pkg) {
      // Ubuntu/Debian do not ship /etc/apt/security.sources.list. Pointing
      // Dir::Etc::SourceList there made apt ignore the override and emit the
      // full upgrade set again, so fleet counted security == pending.
      // Security is the Inst lines whose origin/pocket mentions security.
      PackageManager.apt =>
        "apt-get -s upgrade 2>/dev/null | grep '^Inst ' | "
            "grep -iE 'security|Debian-Security' || true",
      PackageManager.dnf =>
        'timeout -k 5 20 sudo -n /usr/bin/dnf --color=never --cacheonly '
            'updateinfo list security || true',
      PackageManager.yum =>
        'timeout -k 5 20 sudo -n /usr/bin/yum --color=never --cacheonly '
            'updateinfo list security || true',
      PackageManager.zypper => 'zypper lp --category security',
      PackageManager.apk => 'echo N/A',
      PackageManager.pacman => 'echo N/A',
      PackageManager.unknown => 'echo N/A',
    };
  }

  /// [apply] as sudo sees it, for the sudoers line a hint suggests. A rule
  /// holding the shell's quotes would never match. A name the sudoers rules
  /// would refuse is dropped, leaving the fixed upgrade command: it came from
  /// the host, and pasted as is it could grant `apt-get *`.
  static String applyArgv(
    PackageManager pkg, {
    required bool securityOnly,
    List<String> names = const [],
  }) {
    final cmd = names.length == 1 && isSudoersSafePackageName(pkg, names.first)
        ? _applyOne(pkg, names.first)
        : apply(pkg, securityOnly: securityOnly);
    return cmd.replaceFirst('sudo -n ', '');
  }

  static String apply(
    PackageManager pkg, {
    required bool securityOnly,
    List<String> names = const [],
  }) {
    if (names.length == 1) {
      return _applyOne(pkg, shellSingleQuote(names.first));
    }
    if (securityOnly) {
      return switch (pkg) {
        PackageManager.apt =>
          'sudo -n /usr/bin/apt-get -y -o Dpkg::Options::=--force-confold '
              '-o Dir::Etc::SourceList=/etc/apt/security.sources.list upgrade',
        PackageManager.dnf => 'sudo -n /usr/bin/dnf upgrade -y --security',
        PackageManager.yum => 'sudo -n /usr/bin/yum update -y --security',
        PackageManager.zypper =>
          'sudo -n /usr/bin/zypper --non-interactive patch --category security',
        PackageManager.apk => 'sudo -n /sbin/apk upgrade',
        PackageManager.pacman => 'sudo -n /usr/bin/pacman -Syu --noconfirm',
        PackageManager.unknown => 'echo unsupported; exit 1',
      };
    }
    return switch (pkg) {
      PackageManager.apt =>
        'sudo -n /usr/bin/apt-get -y -o Dpkg::Options::=--force-confold upgrade',
      PackageManager.dnf => 'sudo -n /usr/bin/dnf upgrade -y',
      PackageManager.yum => 'sudo -n /usr/bin/yum update -y',
      PackageManager.zypper => 'sudo -n /usr/bin/zypper --non-interactive update',
      PackageManager.apk => 'sudo -n /sbin/apk upgrade',
      PackageManager.pacman => 'sudo -n /usr/bin/pacman -Syu --noconfirm',
      PackageManager.unknown => 'echo unsupported; exit 1',
    };
  }

  static String _applyOne(PackageManager pkg, String q) {
    return switch (pkg) {
      PackageManager.apt =>
        'sudo -n /usr/bin/apt-get -y -o Dpkg::Options::=--force-confold '
            'install --only-upgrade $q',
      PackageManager.dnf => 'sudo -n /usr/bin/dnf upgrade -y $q',
      PackageManager.yum => 'sudo -n /usr/bin/yum update -y $q',
      PackageManager.zypper =>
        'sudo -n /usr/bin/zypper --non-interactive update $q',
      PackageManager.apk => 'sudo -n /sbin/apk add -u $q',
      PackageManager.pacman => 'sudo -n /usr/bin/pacman -S --noconfirm $q',
      PackageManager.unknown => 'echo unsupported; exit 1',
    };
  }
}
