import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
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
    this.limit = 200,
  });

  final String? unit;
  final int? priority;
  final String? grep;
  final String? untilUsec;
  final int limit;

  @override
  String command(HostFacts facts) {
    final args = StringBuffer(
      'journalctl -o json --no-pager -n $limit --reverse',
    );
    final u = unit?.trim();
    if (u != null && u.isNotEmpty) {
      args.write(' -u ${shellSingleQuote(u)}');
    }
    if (priority != null) {
      args.write(' -p $priority');
    }
    final g = grep?.trim();
    if (g != null && g.isNotEmpty) {
      args.write(' --grep ${shellSingleQuote(g)}');
    }
    if (untilUsec != null && untilUsec!.isNotEmpty) {
      final sec = (int.tryParse(untilUsec!) ?? 0) ~/ 1000000;
      if (sec > 0) {
        args.write(' --until @$sec');
      }
    }
    final inner = args.toString();
    final prefix = 'LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0';
    if (!facts.hasJournald) {
      return 'echo "---NOJOURNAL---"';
    }
    if (facts.journalReadable) {
      return '$prefix $inner';
    }
    return '$prefix sudo -n $inner';
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
    if (looksLikeSudoPasswordPrompt(stderr) ||
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
  Duration get timeout => const Duration(seconds: 25);
}
