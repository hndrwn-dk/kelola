import 'dart:convert';

import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/units/shell_quote.dart';

class JournalParser {
  const JournalParser();

  JournalPage parse(String stdout, String stderr) {
    final permission = looksLikeJournalDenied(stderr) ||
        looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeJournalDenied(stdout);
    final entries = <JournalEntry>[];
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed[0] != '{') {
        continue;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          continue;
        }
        final map = decoded.cast<String, dynamic>();
        final message = _message(map['MESSAGE']);
        if (message == null) {
          continue;
        }
        entries.add(
          JournalEntry(
            cursor: (map['__CURSOR'] ?? '').toString(),
            realtimeUsec: (map['__REALTIME_TIMESTAMP'] ?? '').toString(),
            priority: int.tryParse((map['PRIORITY'] ?? '6').toString()) ?? 6,
            message: message,
            unit: _string(map['_SYSTEMD_UNIT'] ?? map['UNIT']),
            syslogIdentifier: _string(map['SYSLOG_IDENTIFIER']),
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return JournalPage(
      entries: entries,
      permissionDenied: permission && entries.isEmpty,
    );
  }

  static bool looksLikeJournalDenied(String text) {
    final s = text.toLowerCase();
    return s.contains('permission denied') ||
        s.contains('not in the systemd-journal') ||
        s.contains('no journal files');
  }

  static String? _string(dynamic raw) {
    if (raw == null) {
      return null;
    }
    final s = raw.toString();
    return s.isEmpty ? null : s;
  }

  static String? _message(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return raw;
    }
    if (raw is List) {
      final bytes = raw.whereType<int>().toList();
      if (bytes.isEmpty) {
        return raw.join();
      }
      return utf8.decode(bytes, allowMalformed: true);
    }
    return raw.toString();
  }
}
