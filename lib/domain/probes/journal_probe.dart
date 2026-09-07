import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/journal/journal_parser.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class JournalProbe extends Probe<JournalPage> {
  const JournalProbe({
    this.unit,
    this.priority,
    this.grep,
    this.untilUsec,
    this.sinceUsec,
    this.limit = 200,
    this.reverse = true,
    this.scope = JournalScope.all,
  });

  final String? unit;
  final int? priority;
  final String? grep;
  final String? untilUsec;
  final String? sinceUsec;
  final int limit;
  final bool reverse;
  final JournalScope scope;

  String get _filters {
    return journalctlFilters(
      unit: unit,
      priority: priority,
      grep: grep,
      untilUsec: untilUsec,
      sinceUsec: sinceUsec,
      reverse: reverse,
      scope: scope,
    );
  }

  String get filterSummary {
    final bits = <String>[
      if (scope != JournalScope.all) scope.name,
      if (unit != null && unit!.trim().isNotEmpty) unit!.trim(),
      if (priority == 3) 'err+',
      if (priority == 4) 'warn+',
      if (grep != null && grep!.trim().isNotEmpty) 'grep=${grep!.trim()}',
      if (sinceUsec != null && sinceUsec!.isNotEmpty) 'since',
      if (untilUsec != null && untilUsec!.isNotEmpty) 'until',
    ];
    return bits.isEmpty ? 'all journals' : bits.join(' · ');
  }

  @override
  String command(HostFacts facts) {
    final access = facts.effectiveJournalAccess;
    if (access == JournalAccess.denied) {
      if (!facts.hasJournald) {
        return 'echo "---LOG_DENIED---"\n';
      }
      return '''
printf '%s\\n' "---KELOLA_J---"
printf 'mode=%s\\n' "denied_perm"
printf 'exit=%s\\n' "1"
printf '%s\\n' "---STDERR---"
printf '%s\\n' "Cached: journal not readable without a password. Fix ACLs or NOPASSWD; Kelola will not retry sudo."
printf '%s\\n' "---STDOUT---"
''';
    }
    if (!facts.hasJournald) {
      final triedSudo = access == JournalAccess.unknown ||
          access == JournalAccess.sudo;
      return '''
LC_ALL=C
set +e
path=\$(
${syslogSelectPathScript(access)}
)
if [ -z "\$path" ]; then
  echo "---NOSYSLOG---"
  ${triedSudo ? 'echo "kelola_access=denied"' : 'echo "kelola_access=missing"'}
  exit 0
fi
echo "---SYSLOG---"
if [ "\${path#SUDO:}" != "\$path" ]; then
  echo "kelola_access=sudo"
  sudo -n tail -n $limit "\${path#SUDO:}"
  exit 0
fi
echo "kelola_access=plain"
tail -n $limit "\$path"
''';
    }
    final f = _filters;
    // Temp files — never `out=\$(journalctl…)` and never `grep -q '{'`.
    final emitFn = '''
td=\$(mktemp -d 2>/dev/null || (mkdir -p /tmp/kelola-j-\$\$ && echo /tmp/kelola-j-\$\$))
emit() {
  printf '%s\\n' "---KELOLA_J---"
  printf 'mode=%s\\n' "\$1"
  printf 'exit=%s\\n' "\$2"
  printf '%s\\n' "---STDERR---"
  cat "\$3" 2>/dev/null
  printf '%s\\n' "---STDOUT---"
  cat "\$4" 2>/dev/null
}
''';
    switch (access) {
      case JournalAccess.plain:
        return '''
LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0
set +e
$emitFn
journalctl -o json --no-pager -n $limit $journalctlOutputFields$f >"\$td/out" 2>"\$td/err"
ec=\$?
if [ "\$ec" -eq 0 ]; then
  emit plain "\$ec" "\$td/err" "\$td/out"
  rm -rf "\$td"
  exit 0
fi
err=\$(cat "\$td/err" 2>/dev/null)
case "\$err" in
  *[Pp]ermission*|*not in the systemd-journal*|*No journal files*|*Failed to open*)
    emit denied_perm "\$ec" "\$td/err" "\$td/out"
    rm -rf "\$td"
    exit 0
    ;;
esac
emit failed "\$ec" "\$td/err" "\$td/out"
rm -rf "\$td"
''';
      case JournalAccess.sudo:
        return '''
LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0
set +e
$emitFn
sudo -n journalctl -o json --no-pager -n $limit $journalctlOutputFields$f >"\$td/out" 2>"\$td/err"
ec=\$?
if [ "\$ec" -eq 0 ]; then
  emit sudo "\$ec" "\$td/err" "\$td/out"
  rm -rf "\$td"
  exit 0
fi
err=\$(cat "\$td/err" 2>/dev/null)
case "\$err" in
  *password*|*askpass*|*a terminal is required*|*no tty*|*No askpass*|*interactive authentication*)
    emit sudo_password "\$ec" "\$td/err" "\$td/out"
    rm -rf "\$td"
    exit 0
    ;;
  *[Pp]ermission*|*not in the systemd-journal*|*No journal files*|*Failed to open*)
    emit denied_perm "\$ec" "\$td/err" "\$td/out"
    rm -rf "\$td"
    exit 0
    ;;
esac
emit failed "\$ec" "\$td/err" "\$td/out"
rm -rf "\$td"
''';
      case JournalAccess.unknown:
      case JournalAccess.denied:
        break;
    }
    return '''
LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0
set +e
$emitFn
journalctl -o json --no-pager -n $limit $journalctlOutputFields$f >"\$td/out" 2>"\$td/err"
ec=\$?
if [ "\$ec" -eq 0 ]; then
  emit plain "\$ec" "\$td/err" "\$td/out"
  rm -rf "\$td"
  exit 0
fi
sudo -n journalctl -o json --no-pager -n $limit $journalctlOutputFields$f >"\$td/out2" 2>"\$td/err2"
ec2=\$?
if [ "\$ec2" -eq 0 ]; then
  emit sudo "\$ec2" "\$td/err2" "\$td/out2"
  rm -rf "\$td"
  exit 0
fi
err2=\$(cat "\$td/err2" 2>/dev/null)
case "\$err2" in
  *password*|*askpass*|*a terminal is required*|*no tty*|*No askpass*|*interactive authentication*)
    emit sudo_password "\$ec2" "\$td/err2" "\$td/out2"
    rm -rf "\$td"
    exit 0
    ;;
  *[Pp]ermission*|*not in the systemd-journal*|*No journal files*|*Failed to open*)
    emit denied_perm "\$ec2" "\$td/err2" "\$td/out2"
    rm -rf "\$td"
    exit 0
    ;;
esac
err=\$(cat "\$td/err" 2>/dev/null)
case "\$err" in
  *[Pp]ermission*|*not in the systemd-journal*|*No journal files*|*Failed to open*)
    emit denied_perm "\$ec" "\$td/err" "\$td/out"
    rm -rf "\$td"
    exit 0
    ;;
esac
emit failed "\$ec" "\$td/err" "\$td/out"
rm -rf "\$td"
''';
  }

  @override
  JournalPage parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---LOG_DENIED---')) {
      return const JournalPage(
        entries: [],
        permissionDenied: true,
        hasJournald: false,
        noReadableLogSource: true,
        learnedAccess: JournalAccess.denied,
        emptyHint:
            'Log files are not readable without a password. Kelola will not retry sudo.',
      );
    }
    if (stdout.contains('---NOSYSLOG---')) {
      final nosysAccess =
          RegExp(r'^kelola_access=(plain|sudo|denied|missing)$', multiLine: true)
              .firstMatch(stdout)
              ?.group(1);
      final learned = switch (nosysAccess) {
        'denied' => JournalAccess.denied,
        'sudo' => JournalAccess.sudo,
        'plain' => JournalAccess.plain,
        _ => null,
      };
      return JournalPage(
        entries: const [],
        permissionDenied: learned == JournalAccess.denied,
        hasJournald: false,
        noReadableLogSource: true,
        learnedAccess: learned,
        emptyHint: learned == JournalAccess.denied
            ? 'Log files are not readable without a password. Kelola will not retry sudo.'
            : 'No journald and no readable /var/log/syslog or /var/log/messages.',
      );
    }
    if (stdout.contains('---NOJOURNAL---')) {
      return const JournalPage(
        entries: [],
        permissionDenied: false,
        hasJournald: false,
      );
    }
    if (stdout.contains('---KELOLA_J---')) {
      return _parseMarked(stdout);
    }
    if (stdout.contains('---SYSLOG---')) {
      final accessMatch = RegExp(r'^kelola_access=(plain|sudo)$', multiLine: true)
          .firstMatch(stdout);
      final learned = switch (accessMatch?.group(1)) {
        'sudo' => JournalAccess.sudo,
        _ => JournalAccess.plain,
      };
      final body = stdout
          .replaceFirst(RegExp(r'^.*?---SYSLOG---\r?\n'), '')
          .replaceFirst(RegExp(r'^kelola_access=(plain|sudo)\r?\n'), '');
      final page = const JournalParser().parse(body, stderr);
      return JournalPage(
        entries: page.entries,
        permissionDenied: false,
        hasJournald: false,
        usedSyslog: true,
        learnedAccess: learned,
        emptyHint: page.emptyHint ??
            (page.entries.isEmpty
                ? 'Syslog is readable but returned no parseable lines.'
                : null),
        skippedLines: page.skippedLines,
      );
    }
    if (looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      return const JournalPage(
        entries: [],
        permissionDenied: false,
        learnedAccess: JournalAccess.denied,
        emptyHint:
            'sudo needs a password for journalctl. Kelola will not prompt; use NOPASSWD or fix journal ACLs for this user.',
      );
    }
    final page = const JournalParser().parse(stdout, stderr);
    if (exitCode != 0 && page.entries.isEmpty) {
      final err = stderr.trim();
      if (JournalParser.looksLikeJournalDenied(err) ||
          JournalParser.looksLikeJournalDenied(stdout)) {
        return const JournalPage(
          entries: [],
          permissionDenied: true,
          learnedAccess: JournalAccess.denied,
        );
      }
      return JournalPage(
        entries: const [],
        permissionDenied: false,
        emptyHint: err.isEmpty
            ? 'journalctl failed (exit $exitCode).'
            : 'journalctl failed (exit $exitCode): $err',
      );
    }
    if (page.entries.isEmpty) {
      return JournalPage(
        entries: const [],
        permissionDenied: false,
        learnedAccess: JournalAccess.plain,
        emptyHint: 'No log lines for filter: $filterSummary.',
        skippedLines: page.skippedLines,
      );
    }
    return JournalPage(
      entries: page.entries,
      permissionDenied: false,
      learnedAccess: JournalAccess.plain,
      emptyHint: page.emptyHint,
      skippedLines: page.skippedLines,
    );
  }

  JournalPage _parseMarked(String stdout) {
    final mode = RegExp(r'^mode=(.+)$', multiLine: true)
            .firstMatch(stdout)
            ?.group(1)
            ?.trim() ??
        '';
    final remoteExit = int.tryParse(
          RegExp(r'^exit=(-?\d+)$', multiLine: true)
                  .firstMatch(stdout)
                  ?.group(1) ??
              '',
        ) ??
        -1;
    final stderrBody = _section(stdout, '---STDERR---', '---STDOUT---');
    final stdoutBody = _section(stdout, '---STDOUT---', null);
    final page = const JournalParser().parse(stdoutBody, stderrBody);

    switch (mode) {
      case 'plain':
        if (page.entries.isEmpty) {
          return JournalPage(
            entries: const [],
            permissionDenied: false,
            learnedAccess: JournalAccess.plain,
            emptyHint: 'No log lines for filter: $filterSummary.',
            skippedLines: page.skippedLines,
          );
        }
        return JournalPage(
          entries: page.entries,
          permissionDenied: false,
          learnedAccess: JournalAccess.plain,
          emptyHint: page.emptyHint,
          skippedLines: page.skippedLines,
        );
      case 'sudo':
        if (page.entries.isEmpty) {
          return JournalPage(
            entries: const [],
            permissionDenied: false,
            learnedAccess: JournalAccess.sudo,
            emptyHint: 'No log lines for filter: $filterSummary.',
            skippedLines: page.skippedLines,
          );
        }
        return JournalPage(
          entries: page.entries,
          permissionDenied: false,
          learnedAccess: JournalAccess.sudo,
          emptyHint: page.emptyHint,
          skippedLines: page.skippedLines,
        );
      case 'denied_perm':
        return JournalPage(
          entries: const [],
          permissionDenied: true,
          learnedAccess: JournalAccess.denied,
          emptyHint: stderrBody.trim().isEmpty ? null : stderrBody.trim(),
        );
      case 'sudo_password':
        return JournalPage(
          entries: const [],
          permissionDenied: false,
          learnedAccess: JournalAccess.denied,
          emptyHint:
              'sudo needs a password for journalctl (exit $remoteExit). '
              'Plain journalctl already failed; this is not the same as '
              '"journal unreadable". Fix ACLs or configure NOPASSWD.',
        );
      case 'failed':
      default:
        final err = stderrBody.trim();
        return JournalPage(
          entries: const [],
          permissionDenied: false,
          emptyHint: err.isEmpty
              ? 'journalctl failed (exit $remoteExit).'
              : 'journalctl failed (exit $remoteExit): $err',
          skippedLines: page.skippedLines,
        );
    }
  }

  static String _section(String raw, String startMark, String? endMark) {
    final start = raw.indexOf(startMark);
    if (start < 0) {
      return '';
    }
    var from = start + startMark.length;
    if (from < raw.length && raw[from] == '\r') {
      from++;
    }
    if (from < raw.length && raw[from] == '\n') {
      from++;
    }
    if (endMark == null) {
      return raw.substring(from);
    }
    final end = raw.indexOf(endMark, from);
    if (end < 0) {
      return raw.substring(from);
    }
    return raw.substring(from, end);
  }

  @override
  bool get needsSudo => false;

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  String get auditTitle {
    final u = unit?.trim();
    if (u == null || u.isEmpty) {
      return 'Read journal';
    }
    return 'Read journal for $u';
  }

  @override
  Duration get timeout => const Duration(seconds: 25);
}

/// What Dart received from the SSH exec (Logs diagnosis). No size cap in
/// dartssh2 [SSHClient.runWithResult]; JournalProbe timeout is 25s.
void logJournalProbeReceive({
  required int? exitCode,
  required List<int> stdout,
  required List<int> stderr,
}) {
  final decoded = utf8.decode(stdout, allowMalformed: true);
  final prefix =
      decoded.length <= 200 ? decoded : decoded.substring(0, 200);
  debugPrint(
    'JournalProbe recv exit=$exitCode stdoutLen=${stdout.length} '
    'stderrLen=${stderr.length} prefix=${jsonEncode(prefix)}',
  );
}
