enum JournalScope {
  all,
  system,
  user,
}

extension JournalScopeX on JournalScope {
  /// Flag fragment including leading space, or empty for [JournalScope.all].
  String get journalctlFlag {
    switch (this) {
      case JournalScope.all:
        return '';
      case JournalScope.system:
        return ' --system';
      case JournalScope.user:
        return ' --user';
    }
  }

  String get kickerLabel {
    switch (this) {
      case JournalScope.all:
        return 'ALL JOURNALS';
      case JournalScope.system:
        return 'SYSTEM';
      case JournalScope.user:
        return 'USER';
    }
  }
}

String journalKicker({
  String? unit,
  int? priority,
  JournalScope scope = JournalScope.all,
  bool syslog = false,
}) {
  final sev = switch (priority) {
    3 => 'ERR+',
    4 => 'WARN+',
    _ => 'ALL',
  };
  if (syslog) {
    return 'SYSLOG · $sev';
  }
  final name = (unit == null || unit.trim().isEmpty)
      ? scope.kickerLabel
      : unit.trim().toUpperCase();
  return '$name · $sev';
}

String journalClock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
