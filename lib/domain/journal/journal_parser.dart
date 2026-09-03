import 'dart:convert';

import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Incremental NDJSON decoder for `journalctl -o json`. Keeps only the
/// unfinished tail — never the lines already yielded.
class JournalNdjsonBuffer {
  final StringBuffer _tail = StringBuffer();

  int get pendingBytes => _tail.length;

  List<JournalEntry> add(String chunk) {
    if (chunk.isEmpty) {
      return <JournalEntry>[];
    }
    _tail.write(chunk);
    return _drain(flushIncomplete: false);
  }

  List<JournalEntry> flush() => _drain(flushIncomplete: true);

  List<JournalEntry> _drain({required bool flushIncomplete}) {
    final raw = _tail.toString();
    if (raw.isEmpty) {
      return <JournalEntry>[];
    }
    final entries = <JournalEntry>[];
    var start = 0;
    while (true) {
      final nl = raw.indexOf('\n', start);
      if (nl < 0) {
        break;
      }
      final line = raw.substring(start, nl);
      start = nl + 1;
      final entry = JournalParser.tryParseLine(line);
      if (entry != null) {
        entries.add(entry);
      }
    }
    final leftover = start < raw.length ? raw.substring(start) : '';
    _tail.clear();
    if (flushIncomplete) {
      final entry = JournalParser.tryParseLine(leftover);
      if (entry != null) {
        entries.add(entry);
      }
    } else {
      _tail.write(leftover);
    }
    return entries;
  }
}

class JournalParser {
  const JournalParser();

  JournalPage parse(String stdout, String stderr) {
    final permission = looksLikeJournalDenied(stderr) ||
        looksLikeSudoPasswordPrompt(stderr) ||
        looksLikeJournalDenied(stdout);
    final buf = JournalNdjsonBuffer();
    final entries = buf.add(stdout);
    entries.addAll(buf.flush());
    return JournalPage(
      entries: entries,
      permissionDenied: permission && entries.isEmpty,
      emptyHint: entries.isEmpty && !permission
          ? 'journalctl returned no JSON lines. The SSH user needs the systemd-journal group or passwordless sudo.'
          : null,
    );
  }

  static JournalEntry? tryParseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed[0] != '{') {
      return _tryParseSyslog(trimmed);
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      final map = decoded.cast<String, dynamic>();
      final message = _message(map['MESSAGE']);
      if (message == null) {
        return null;
      }
      return JournalEntry(
        cursor: (map['__CURSOR'] ?? '').toString(),
        realtimeUsec: (map['__REALTIME_TIMESTAMP'] ?? '').toString(),
        priority: int.tryParse((map['PRIORITY'] ?? '6').toString()) ?? 6,
        message: message,
        unit: _string(map['_SYSTEMD_UNIT'] ?? map['UNIT']),
        syslogIdentifier: _string(map['SYSLOG_IDENTIFIER']),
      );
    } on FormatException {
      return null;
    }
  }

  static final _isoSyslog = RegExp(
    r'^(\d{4}-\d{2}-\d{2}T\S+)\s+\S+\s+([^:[]+)(?:\[\d+\])?:\s*(.*)$',
  );

  static JournalEntry? _tryParseSyslog(String line) {
    if (line.isEmpty) {
      return null;
    }
    final match = _isoSyslog.firstMatch(line);
    if (match == null) {
      return null;
    }
    final message = match.group(3) ?? '';
    if (message.isEmpty) {
      return null;
    }
    final ident = match.group(2)!.trim();
    final stamp = DateTime.tryParse(match.group(1)!);
    final usec = stamp?.toUtc().microsecondsSinceEpoch.toString() ?? '';
    return JournalEntry(
      cursor: 'syslog:$usec:$ident:$message',
      realtimeUsec: usec,
      priority: 6,
      message: message,
      syslogIdentifier: ident,
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
