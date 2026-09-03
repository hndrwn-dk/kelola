import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_follow.dart';
import 'package:kelola/domain/journal/journal_parser.dart';
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
  });

  final String? unit;
  final int? priority;
  final String? grep;
  final String? untilUsec;
  final String? sinceUsec;
  final int limit;
  final bool reverse;

  String get _filters {
    return journalctlFilters(
      unit: unit,
      priority: priority,
      grep: grep,
      untilUsec: untilUsec,
      sinceUsec: sinceUsec,
      reverse: reverse,
    );
  }

  @override
  String command(HostFacts facts) {
    if (!facts.hasJournald) {
      return 'echo "---NOJOURNAL---"';
    }
    final f = _filters;
    return '''
LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0
set +e
out=\$(journalctl -o json --no-pager -n $limit --system$f 2>/dev/null)
if printf '%s' "\$out" | grep -q '{'; then
  printf '%s\\n' "\$out"
  exit 0
fi
out=\$(sudo -n journalctl -o json --no-pager -n $limit --system$f 2>/dev/null)
if printf '%s' "\$out" | grep -q '{'; then
  printf '%s\\n' "\$out"
  exit 0
fi
echo "---DENIED---"
''';
  }

  @override
  JournalPage parse(String stdout, String stderr, int exitCode) {
    if (stdout.contains('---NOJOURNAL---')) {
      return const JournalPage(
        entries: [],
        permissionDenied: false,
        hasJournald: false,
      );
    }
    if (stdout.contains('---DENIED---') ||
        looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeSudoPasswordPrompt(stdout)) {
      return const JournalPage(entries: [], permissionDenied: true);
    }
    return const JournalParser().parse(stdout, stderr);
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
