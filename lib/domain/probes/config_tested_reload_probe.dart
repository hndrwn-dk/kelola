import 'package:kelola/domain/exceptions.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/web_lens_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

enum ReloadOutcome {
  /// Config test passed and the reload command exited 0.
  reloaded,

  /// The config test failed; nothing was reloaded.
  testFailed,

  /// Refused before running, cut output, or the reload command failed.
  failed,
}

class ReloadResult {
  const ReloadResult({
    required this.outcome,
    this.testOutput = '',
    this.activeState,
    this.reloadOutput = '',
    this.reason,
  });

  final ReloadOutcome outcome;

  /// Output of `<testBin> -t` (host text, shown in mono).
  final String testOutput;

  /// `ActiveState` (systemd) or OpenRC status word after the reload.
  final String? activeState;

  /// Output of the reload command when it failed (host text).
  final String reloadOutput;

  /// App-written copy for a [ReloadOutcome.failed] that has no host output.
  final String? reason;
}

/// Whether [unit] and [testBin] (both from detection, so host-derived) are
/// safe to put in [ConfigTestedReloadProbe]'s command. The screen offers
/// Reload only when this holds.
bool isSafeReloadTarget({
  required ServiceId id,
  required String? unit,
  required String? testBin,
}) {
  if (safeWebUnit(unit) == null || testBin == null) return false;
  return webConfigTestBinaryNames(id).any(
    (n) => isSafeWebBinaryPath(testBin, n),
  );
}

/// M52 §6: the lens's only mutating probe. Tests the config with
/// `sudo -n <testBin> -t`, and only if that exits 0 reloads the service
/// (`sudo -n systemctl reload <unit>`, the PR #17 grant argv; OpenRC
/// `sudo -n rc-service <svc> reload`), then reads its state back.
///
/// Same framing as [WebLensProbe]: markers and `@key=value` lines are written
/// by the script; host output is printed with a `|` prefix, so it cannot forge
/// either. An unsafe [unit] / [testBin] or an unsupported init system yields a
/// script that runs nothing (`@refused=…`, exit 2).
class ConfigTestedReloadProbe extends Probe<ReloadResult> {
  const ConfigTestedReloadProbe({
    required this.id,
    required this.unit,
    required this.testBin,
  });

  /// [ServiceId.nginx] or [ServiceId.apache].
  final ServiceId id;

  /// Detected unit (`nginx.service`) or OpenRC service (`nginx`).
  final String unit;

  /// Detected absolute path of the config tester (`/usr/sbin/nginx`,
  /// `/usr/sbin/apachectl`).
  final String testBin;

  /// Max test / reload output lines kept.
  static const _maxLines = 60;
  static const _maxLineLength = 2000;

  bool get _apache => id == ServiceId.apache;

  String get _service => _apache ? 'apache' : 'nginx';

  @override
  String get auditTitle => _apache
      ? 'Reloaded Apache (config tested)'
      : 'Reloaded nginx (config tested)';

  @override
  bool get needsSudo => true;

  @override
  RiskLevel get risk => RiskLevel.mutate;

  @override
  Duration get timeout => const Duration(seconds: 30);

  @override
  String command(HostFacts facts) {
    if (!isSafeReloadTarget(id: id, unit: unit, testBin: testBin)) {
      return 'echo @refused=unsafe\nexit 2';
    }
    final u = shellSingleQuote(unit);
    final b = shellSingleQuote(testBin);
    final String init;
    final String reload;
    final String verify;
    switch (facts.init) {
      case InitSystem.systemd:
        init = 'systemd';
        reload = 'sudo -n systemctl reload $u';
        verify = 'systemctl show $u -p ActiveState -p SubState --no-pager';
      case InitSystem.openrc:
        init = 'openrc';
        reload = 'sudo -n rc-service $u reload';
        verify = 'rc-service $u status';
      case InitSystem.sysvinit:
      case InitSystem.unknown:
        return 'echo @refused=init\nexit 2';
    }
    return [
      webSbinPathLine,
      'export LC_ALL=C',
      webOutShellFn,
      'echo @init=$init',
      'echo ---TEST---',
      'o=\$(sudo -n $b -t 2>&1 </dev/null); rc=\$?',
      'if ${webSudoRefusedCondition('rc', 'o')}; then rc=nosudo; o=; fi',
      r'out "$o"',
      r'echo "@rc=$rc"',
      // A refused sudo is not a config error; neither reaches the reload.
      r'case "$rc" in nosudo) exit 4 ;; esac',
      r'[ "$rc" = 0 ] || exit 3',
      'echo ---RELOAD---',
      'o=\$($reload 2>&1 </dev/null); r=\$?',
      'if ${webSudoRefusedCondition('r', 'o')}; then r=nosudo; o=; fi',
      r'out "$o"',
      r'echo "@rc=$r"',
      'echo ---VERIFY---',
      'o=\$($verify 2>&1 </dev/null)',
      r'out "$o"',
      r'[ "$r" = 0 ]',
    ].join('\n');
  }

  @override
  ReloadResult parse(String stdout, String stderr, int exitCode) {
    final sections = <String, _Section>{};
    final global = _Section();
    var cur = global;
    var skip = false;
    for (final raw in stdout.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      if (line.startsWith('|')) {
        if (!skip) cur.data.add(line.substring(1));
        continue;
      }
      final m = RegExp(r'^---(TEST|RELOAD|VERIFY)---$').firstMatch(line);
      if (m != null) {
        final name = m.group(1)!;
        // First occurrence wins; a repeat would only come from a broken script.
        skip = sections.containsKey(name);
        if (!skip) cur = sections[name] = _Section();
        continue;
      }
      if (line.startsWith('@') && !skip) {
        final eq = line.indexOf('=');
        if (eq > 1) {
          cur.meta.putIfAbsent(line.substring(1, eq), () => line.substring(eq + 1));
        }
      }
      // Anything else is junk (stderr noise, a cut line): ignored.
    }

    final refused = global.meta['refused'];
    if (refused != null) {
      return ReloadResult(
        outcome: ReloadOutcome.failed,
        reason: refused == 'init'
            ? 'Reload is not supported on this init system.'
            : 'Service unit unknown.',
      );
    }

    final test = sections['TEST'];
    final testRc = test?.meta['rc'];
    final testOutput = _text(test?.data);
    if (testRc == 'nosudo' ||
        (testRc == null && looksLikeSudoPasswordPrompt(stderr))) {
      throw SudoRequiredException(
        SudoHintContext.webServices(service: _service),
      );
    }
    if (testRc == null || !_isInt(testRc)) {
      return const ReloadResult(
        outcome: ReloadOutcome.failed,
        reason: 'The config test did not run.',
      );
    }
    if (testRc != '0') {
      if (testOutput.isEmpty) {
        return ReloadResult(
          outcome: ReloadOutcome.failed,
          reason: 'The config test exited $testRc with no output.',
        );
      }
      return ReloadResult(
        outcome: ReloadOutcome.testFailed,
        testOutput: testOutput,
      );
    }

    final reload = sections['RELOAD'];
    final reloadRc = reload?.meta['rc'];
    if (reloadRc == 'nosudo') {
      // systemd: the PR #17 per-unit grant can be offered; OpenRC has none.
      throw SudoRequiredException(
        global.meta['init'] == 'systemd'
            ? SudoHintContext.systemd(unit: unit, verb: 'reload')
            : SudoHintContext.webServices(
                service: _service,
                binary: webOpenRcReloadBinary,
              ),
      );
    }
    final reloadOutput = _text(reload?.data);
    if (reloadRc == null || !_isInt(reloadRc)) {
      return ReloadResult(
        outcome: ReloadOutcome.failed,
        testOutput: testOutput,
        reason: 'The reload did not report a result.',
      );
    }
    final activeState = _state(sections['VERIFY']?.data);
    if (reloadRc != '0') {
      return ReloadResult(
        outcome: ReloadOutcome.failed,
        testOutput: testOutput,
        reloadOutput: reloadOutput,
        activeState: activeState,
        reason: 'The reload exited $reloadRc.',
      );
    }
    return ReloadResult(
      outcome: ReloadOutcome.reloaded,
      testOutput: testOutput,
      activeState: activeState,
    );
  }

  static String _text(List<String>? lines) {
    if (lines == null) return '';
    final kept = [
      for (final l in lines)
        if (l.trim().isNotEmpty)
          l.length > _maxLineLength ? l.substring(0, _maxLineLength) : l,
    ];
    final tail = kept.length > _maxLines
        ? kept.sublist(kept.length - _maxLines)
        : kept;
    return tail.join('\n');
  }

  static bool _isInt(String s) =>
      s.isNotEmpty &&
      s.length <= 4 &&
      s.codeUnits.every((c) => c >= 48 && c <= 57);

  /// `ActiveState=active` (systemctl show) or ` * status: started` (OpenRC).
  static String? _state(List<String>? lines) {
    if (lines == null) return null;
    final word = RegExp(r'^[a-z-]{1,32}$');
    for (final raw in lines) {
      final l = raw.trim();
      String? v;
      if (l.startsWith('ActiveState=')) {
        v = l.substring('ActiveState='.length).trim();
      } else {
        final i = l.indexOf('status:');
        if (i >= 0) v = l.substring(i + 7).trim();
      }
      if (v != null && word.hasMatch(v)) return v;
    }
    return null;
  }
}

class _Section {
  final data = <String>[];
  final meta = <String, String>{};
}
