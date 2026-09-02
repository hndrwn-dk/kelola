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
    this.emptyHint,
  });

  final List<JournalEntry> entries;
  final bool permissionDenied;
  final bool hasJournald;
  final String? emptyHint;

  String? get olderThanUsec {
    if (entries.isEmpty) {
      return null;
    }
    return entries.last.realtimeUsec;
  }
}
