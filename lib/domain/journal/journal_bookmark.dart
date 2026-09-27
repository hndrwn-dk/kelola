import 'package:kelola/domain/journal/journal_view.dart';

const kJournalBookmarkCap = 50;

class JournalBookmark {
  const JournalBookmark({
    required this.id,
    required this.hostId,
    required this.label,
    required this.query,
    required this.scope,
    required this.lastHour,
    required this.createdAt,
    this.unit,
    this.priority,
  });

  final String id;
  final String hostId;
  final String label;
  final String? unit;
  final String query;
  final JournalScope scope;
  final int? priority;
  final bool lastHour;
  final DateTime createdAt;

  JournalBookmark copyWith({
    String? hostId,
    String? label,
    String? unit,
    String? query,
    JournalScope? scope,
    int? priority,
    bool? lastHour,
    DateTime? createdAt,
  }) {
    return JournalBookmark(
      id: id,
      hostId: hostId ?? this.hostId,
      label: label ?? this.label,
      unit: unit ?? this.unit,
      query: query ?? this.query,
      scope: scope ?? this.scope,
      priority: priority ?? this.priority,
      lastHour: lastHour ?? this.lastHour,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

String journalBookmarkLabel({
  String? unit,
  required String query,
  required JournalScope scope,
  int? priority,
  required bool lastHour,
}) {
  final parts = <String>[
    journalKicker(unit: unit, priority: priority, scope: scope),
  ];
  if (lastHour) {
    parts.add('1H');
  }
  final q = query.trim();
  if (q.isNotEmpty) {
    parts.add(q);
  }
  return parts.join(' · ');
}

bool sameJournalBookmark(JournalBookmark a, JournalBookmark b) {
  return a.hostId == b.hostId &&
      (a.unit ?? '').trim() == (b.unit ?? '').trim() &&
      a.query.trim().toLowerCase() == b.query.trim().toLowerCase() &&
      a.scope == b.scope &&
      a.priority == b.priority &&
      a.lastHour == b.lastHour;
}

JournalScope journalScopeFromName(String raw) {
  for (final scope in JournalScope.values) {
    if (scope.name == raw) {
      return scope;
    }
  }
  return JournalScope.all;
}
