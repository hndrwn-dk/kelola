import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detect_parser.dart';
import 'package:kelola/domain/services/service_detection.dart';

/// M52 §2a: one batched read that lists which known services a host runs.
/// Every command fragment comes from [kServiceCatalog] constants; nothing
/// host-derived is interpolated.
class ServiceDetectProbe extends Probe<ServiceDetection> {
  const ServiceDetectProbe();

  @override
  String get auditTitle => 'Detected services';

  @override
  String command(HostFacts facts) {
    return [
      // Debian's non-root PATH has no sbin dirs (nginx, apache2, apachectl);
      // appended, so the login's own order wins. Same as webSbinPathLine.
      r'PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"; export PATH',
      'export LC_ALL=C',
      'echo ---UNITS---',
      ..._unitsLines(facts.init),
      'echo ---BIN---',
      'for b in ${_binaryNames().join(' ')}; do',
      '  p=\$(command -v "\$b" 2>/dev/null) && echo "\$b \$p"',
      'done',
      'echo ---VERSION---',
      ..._versionLines(),
      'echo ---PORTS---',
      // No -p: the owning process needs root, and guessing it from a port
      // would be fabrication.
      "ss -Hltn 2>/dev/null | awk '{print \$4}'",
      'true',
    ].join('\n');
  }

  List<String> _unitsLines(InitSystem init) {
    switch (init) {
      case InitSystem.systemd:
        // UNIT LOAD ACTIVE SUB -> unit, ActiveState, SubState. Units that
        // are only referenced (LOAD not-found) do not exist on the host.
        return [
          'systemctl list-units --type=service --all --no-legend --plain '
              "--no-pager 2>/dev/null | awk '\$2 != \"not-found\" "
              "{print \$1, \$3, \$4}'",
        ];
      case InitSystem.openrc:
        return ['rc-status -a 2>/dev/null'];
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return const [];
    }
  }

  List<String> _binaryNames() {
    final seen = <String>{};
    return [
      for (final d in kServiceCatalog)
        for (final b in d.binaries)
          if (seen.add(b)) b,
    ];
  }

  List<String> _versionLines() {
    final out = <String>[];
    for (final d in kServiceCatalog) {
      final cmd = d.versionCommand;
      if (cmd == null) {
        continue;
      }
      // `<bin>` stands for whichever catalog binary is found first;
      // otherwise the command's own first word is the guard.
      final bins = cmd.contains('<bin>')
          ? d.binaries
          : [cmd.split(RegExp(r'\s+')).first];
      final branches = <String>[];
      for (var i = 0; i < bins.length; i++) {
        final b = bins[i];
        branches.add(
          '${i == 0 ? 'if' : 'elif'} command -v $b >/dev/null 2>&1; then '
          "printf '${d.id.name} '; { ${cmd.replaceAll('<bin>', b)}; } | head -1",
        );
      }
      out.add('${branches.join('; ')}; fi');
    }
    return out;
  }

  @override
  ServiceDetection parse(String stdout, String stderr, int exitCode) =>
      parseServiceDetection(stdout, now: DateTime.now());

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Duration get timeout => const Duration(seconds: 10);
}
