const kSessionLogCap = 100;

const kSessionLogBodyCap = 64 * 1024;

const kDefaultSessionLogRetentionDays = 14;

const sessionLogEmptyCopy = 'No session logs on this host yet';

const sessionLogNoMatchCopy = 'No matching session logs';

const _truncatedMark = '\n---TRUNCATED---';

class SessionLog {
  const SessionLog({
    required this.id,
    required this.hostId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.bookmarked = false,
    this.kind = 'command',
  });

  final String id;
  final String hostId;
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool bookmarked;

  SessionLog copyWith({bool? bookmarked}) {
    return SessionLog(
      id: id,
      hostId: hostId,
      kind: kind,
      title: title,
      body: body,
      createdAt: createdAt,
      bookmarked: bookmarked ?? this.bookmarked,
    );
  }
}

enum SessionLogRetention {
  seven(7, '7 days'),
  fourteen(14, '14 days'),
  thirty(30, '30 days'),
  ninety(90, '90 days');

  const SessionLogRetention(this.days, this.label);

  final int days;
  final String label;

  static SessionLogRetention fromDays(int days) {
    for (final value in values) {
      if (value.days == days) {
        return value;
      }
    }
    return SessionLogRetention.fourteen;
  }
}

bool shouldRecordSessionLog(String title) => title.trim().isNotEmpty;

String clipSessionLogBody(String body) {
  if (body.length <= kSessionLogBodyCap) {
    return body;
  }
  final keep = kSessionLogBodyCap - _truncatedMark.length;
  return '${body.substring(0, keep)}$_truncatedMark';
}

List<SessionLog> pruneSessionLogs({
  required Iterable<SessionLog> logs,
  required DateTime now,
  required int retentionDays,
  int cap = kSessionLogCap,
}) {
  final window = Duration(days: SessionLogRetention.fromDays(retentionDays).days);
  final bookmarked = <SessionLog>[];
  final fresh = <SessionLog>[];
  for (final log in logs) {
    if (log.bookmarked) {
      bookmarked.add(log);
      continue;
    }
    if (now.difference(log.createdAt) >= window) {
      continue;
    }
    fresh.add(log);
  }
  fresh.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final capped = fresh.take(cap).toList();
  return [...bookmarked, ...capped];
}

List<SessionLog> filterSessionLogs(List<SessionLog> logs, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return List<SessionLog>.from(logs);
  }
  return logs
      .where(
        (l) =>
            l.title.toLowerCase().contains(q) ||
            l.body.toLowerCase().contains(q),
      )
      .toList();
}
