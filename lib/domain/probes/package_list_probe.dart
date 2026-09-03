import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/packages/package_commands.dart';
import 'package:kelola/domain/packages/package_parser.dart';
import 'package:kelola/domain/packages/package_snapshot.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class PackageListProbe extends Probe<PackageSnapshot> {
  const PackageListProbe();

  @override
  String get auditTitle => 'Listed package updates';

  @override
  String command(HostFacts facts) {
    final pkg = facts.pkg;
    if (pkg == PackageManager.unknown) {
      return 'echo unsupported; exit 1';
    }
    final list = PackageCommands.listUpdates(pkg);
    final security = PackageCommands.listSecurity(pkg);
    return '''
LC_ALL=C
echo "---PKG---"
echo ${pkg.name}
echo "---UPDATES---"
$list || true
echo "---SECURITY---"
$security || true
echo "---REBOOT---"
if [ -f /var/run/reboot-required ]; then
  echo FILE
  cat /var/run/reboot-required.pkgs 2>/dev/null || true
fi
if command -v needs-restarting >/dev/null 2>&1; then
  needs-restarting -r >/dev/null 2>&1
  echo NEEDS_RESTARTING_R:\$?
  needs-restarting 2>/dev/null | head -20 || true
fi
''';
  }

  @override
  PackageSnapshot parse(String stdout, String stderr, int exitCode) {
    if (exitCode != 0 && stdout.trim() == 'unsupported') {
      throw KelolaException('No package manager on this host.');
    }
    final pkg = _pkgFrom(stdout);
    return const PackageParser().parse(
      manager: pkg,
      stdout: stdout,
      stderr: stderr,
      exitCode: exitCode,
    );
  }

  static PackageManager _pkgFrom(String stdout) {
    const marker = '---PKG---';
    final i = stdout.indexOf(marker);
    if (i < 0) {
      return PackageManager.unknown;
    }
    final rest = stdout.substring(i + marker.length).trimLeft();
    final line = rest.split('\n').first.trim();
    for (final v in PackageManager.values) {
      if (v.name == line) {
        return v;
      }
    }
    return PackageManager.unknown;
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 60);
}
