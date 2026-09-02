String journalKicker({String? unit, int? priority}) {
  final name = (unit == null || unit.trim().isEmpty)
      ? 'SYSTEM'
      : unit.trim().toUpperCase();
  final sev = switch (priority) {
    3 => 'ERR+',
    4 => 'WARN+',
    _ => 'ALL',
  };
  return '$name · $sev';
}

String journalClock(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
