import 'package:kelola/domain/facts/enums.dart';

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
      PackageManager.dnf => 'dnf check-update --refresh',
      PackageManager.yum => 'yum check-update',
      PackageManager.zypper => 'zypper -q lu',
      PackageManager.apk => "apk version -l '<'",
      PackageManager.pacman =>
        'if command -v checkupdates >/dev/null 2>&1; then checkupdates; else pacman -Qu; fi',
      PackageManager.unknown => 'echo unsupported; exit 1',
    };
  }

  static String listSecurity(PackageManager pkg) {
    return switch (pkg) {
      PackageManager.apt =>
        'apt-get -s upgrade -o Dir::Etc::SourceList=/etc/apt/security.sources.list',
      PackageManager.dnf => 'dnf updateinfo list security',
      PackageManager.yum => 'yum updateinfo list security',
      PackageManager.zypper => 'zypper lp --category security',
      PackageManager.apk => 'echo N/A',
      PackageManager.pacman => 'echo N/A',
      PackageManager.unknown => 'echo N/A',
    };
  }

  static String apply(PackageManager pkg, {required bool securityOnly}) {
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
}
