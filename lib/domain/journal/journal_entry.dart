import 'package:kelola/domain/facts/host_facts.dart';

class JournalEntry {
  const JournalEntry({
    required this.cursor,
    required this.realtimeUsec,
    required this.priority,
    required this.message,
    this.unit,
    this.syslogIdentifier,
  });

  final String cursor;
  final String realtimeUsec;
  final int priority;
  final String message;
  final String? unit;
  final String? syslogIdentifier;

  DateTime? get timestamp {
    final usec = int.tryParse(realtimeUsec);
    if (usec == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(usec, isUtc: true).toLocal();
  }

  bool get isError => priority <= 3;
  bool get isWarning => priority == 4;
}

class JournalPage {
  const JournalPage({
    required this.entries,
    required this.permissionDenied,
    this.hasJournald = true,
    this.usedSyslog = false,
    this.noReadableLogSource = false,
    this.emptyHint,
    this.skippedLines = 0,
    this.learnedAccess,
  });

  final List<JournalEntry> entries;
  final bool permissionDenied;
  final bool hasJournald;

  /// Historical/live came from syslog because journald is absent.
  final bool usedSyslog;

  /// Neither journald nor a readable syslog/messages file.
  final bool noReadableLogSource;
  final String? emptyHint;

  /// Non-empty stdout lines the parser could not turn into [JournalEntry]s.
  final int skippedLines;

  /// Outcome to persist on the host so sudo is not retried next open.
  final JournalAccess? learnedAccess;

  String? get olderThanUsec {
    if (entries.isEmpty) {
      return null;
    }
    return entries.last.realtimeUsec;
  }
}
