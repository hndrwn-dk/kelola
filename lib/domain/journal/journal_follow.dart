import 'dart:async';
import 'dart:convert';

import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_parser.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/units/shell_quote.dart';

String journalctlFilters({
  String? unit,
  int? priority,
  String? grep,
  String? untilUsec,
  String? sinceUsec,
  bool reverse = false,
  JournalScope scope = JournalScope.all,
}) {
  final args = StringBuffer(scope.journalctlFlag);
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
  if (untilUsec != null && untilUsec.isNotEmpty) {
    final sec = (int.tryParse(untilUsec) ?? 0) ~/ 1000000;
    if (sec > 0) {
      args.write(' --until @$sec');
    }
  }
  if (sinceUsec != null && sinceUsec.isNotEmpty) {
    final sec = (int.tryParse(sinceUsec) ?? 0) ~/ 1000000;
    if (sec > 0) {
      args.write(' --since @$sec');
    }
  }
  if (reverse) {
    args.write(' --reverse');
  }
  return args.toString();
}

bool shouldAcceptFollowEntry(
  JournalEntry incoming,
  Iterable<JournalEntry> existing,
) {
  if (incoming.cursor.isNotEmpty &&
      existing.any((e) => e.cursor == incoming.cursor)) {
    return false;
  }
  if (incoming.realtimeUsec.isNotEmpty &&
      existing.any(
        (e) =>
            e.realtimeUsec == incoming.realtimeUsec &&
            e.message == incoming.message,
      )) {
    return false;
  }
  return true;
}

/// SSH exec for follow must allocate a PTY.
///
/// `journalctl --follow` installs an EPOLLHUP/ERR watch on stdout and
/// exits when that fires. A bare SSH exec presents stdout as a pipe,
/// so journalctl dies immediately, sshd tears down the connection, and
/// logind logs `session-N.scope: Deactivated successfully`. A PTY keeps
/// stdout open and line-buffered. `--no-pager` is required once a PTY
/// exists so `less` does not take over.
const bool journalFollowRequiresPty = true;

/// Fields Kelola actually renders — keeps `-o json` payloads small.
const journalctlOutputFields =
    '--output-fields=__CURSOR,__REALTIME_TIMESTAMP,PRIORITY,'
    '_SYSTEMD_UNIT,UNIT,SYSLOG_IDENTIFIER,MESSAGE';

/// Syslog probe order when journald is absent (Alpine / busybox).
const syslogProbePaths = ['/var/log/syslog', '/var/log/messages'];

/// Shell that prints the first readable syslog path, or nothing.
///
/// [access] gates the `sudo -n test -r` legs (auth-log spam on Alpine).
String syslogSelectPathScript([
  JournalAccess access = JournalAccess.unknown,
]) {
  if (access == JournalAccess.denied) {
    return 'true\n';
  }
  final buf = StringBuffer();
  if (access == JournalAccess.plain || access == JournalAccess.unknown) {
    for (final path in syslogProbePaths) {
      buf.writeln('if [ -r $path ]; then echo $path; exit 0; fi');
    }
  }
  if (access == JournalAccess.sudo || access == JournalAccess.unknown) {
    for (final path in syslogProbePaths) {
      buf.writeln(
        'if sudo -n test -r $path 2>/dev/null; then echo SUDO:$path; exit 0; fi',
      );
    }
  }
  return buf.toString();
}

/// `journalctl -o json --no-pager -f` on a dedicated SSH session. Not [JournalProbe].
class JournalFollowCommand {
  const JournalFollowCommand({
    this.unit,
    this.priority,
    this.grep,
    this.scope = JournalScope.all,
  });

  final String? unit;
  final int? priority;
  final String? grep;
  final JournalScope scope;

  String command(HostFacts facts) {
    final access = facts.effectiveJournalAccess;
    if (access == JournalAccess.denied) {
      return 'echo "---DENIED---"\n';
    }
    if (!facts.hasJournald) {
      final triedSudo = access == JournalAccess.unknown ||
          access == JournalAccess.sudo;
      return '''
LC_ALL=C
set +e
path=\$(
${syslogSelectPathScript(access)}
)
if [ -z "\$path" ]; then
  ${triedSudo ? 'echo "---DENIED---"' : 'echo "---NOSYSLOG---"'}
  exit 0
fi
if [ "\${path#SUDO:}" != "\$path" ]; then
  exec sudo -n tail -n 0 -F "\${path#SUDO:}"
fi
exec tail -n 0 -F "\$path"
''';
    }
    final f = journalctlFilters(
      unit: unit,
      priority: priority,
      grep: grep,
      scope: scope,
    );
    return '''
LC_ALL=C SYSTEMD_PAGER= SYSTEMD_COLORS=0
set +e
${_journalctlFollowLoop(f, access)}
echo "---DENIED---"
''';
  }

  static String _journalctlFollowLoop(String filters, JournalAccess access) {
    switch (access) {
      case JournalAccess.plain:
        return '''
while true; do
  journalctl -o json --no-pager -f -n 0 $journalctlOutputFields$filters
  sleep 1
done
''';
      case JournalAccess.sudo:
        return '''
while true; do
  sudo -n journalctl -o json --no-pager -f -n 0 $journalctlOutputFields$filters
  sleep 1
done
''';
      case JournalAccess.denied:
        return 'echo "---DENIED---"\nexit 0\n';
      case JournalAccess.unknown:
        return '''
while true; do
  if journalctl -o json --no-pager -n 1 $journalctlOutputFields$filters >/dev/null 2>&1; then
    journalctl -o json --no-pager -f -n 0 $journalctlOutputFields$filters
  elif sudo -n journalctl -o json --no-pager -n 1 $journalctlOutputFields$filters >/dev/null 2>&1; then
    sudo -n journalctl -o json --no-pager -f -n 0 $journalctlOutputFields$filters
  else
    echo "---DENIED---"
    exit 0
  fi
  sleep 1
done
''';
    }
  }
}
/// One live `journalctl -f` SSH channel. [close] must drop it.
abstract class JournalFollowChannel {
  Stream<List<int>> get stdout;
  Future<void> close();
  bool get isClosed;
}

class JournalFollowHandle {
  JournalFollowHandle._({required this.channel});

  factory JournalFollowHandle.bind({
    required JournalFollowChannel channel,
    required void Function(JournalEntry entry) onEntry,
    void Function()? onDenied,
    void Function()? onNoSyslog,
    void Function(Object error)? onError,
    void Function()? onClosed,
  }) {
    final handle = JournalFollowHandle._(channel: channel);
    handle._sub = channel.stdout.listen(
      (chunk) {
        final text = utf8.decode(chunk, allowMalformed: true);
        if (text.contains('---NOSYSLOG---')) {
          onNoSyslog?.call();
          return;
        }
        if (text.contains('---DENIED---') || text.contains('---NOJOURNAL---')) {
          onDenied?.call();
          return;
        }
        for (final entry in handle._decoder.add(text)) {
          onEntry(entry);
        }
      },
      onError: (Object e, StackTrace _) => onError?.call(e),
      onDone: () {
        handle._open = false;
        onClosed?.call();
      },
    );
    return handle;
  }

  final JournalFollowChannel channel;
  final JournalNdjsonBuffer _decoder = JournalNdjsonBuffer();
  StreamSubscription<List<int>>? _sub;
  bool _open = true;

  bool get isOpen => _open && !channel.isClosed;

  Future<void> cancel() async {
    _open = false;
    final sub = _sub;
    _sub = null;
    final closing = channel.isClosed ? null : channel.close();
    await sub?.cancel();
    if (closing != null) {
      await closing;
    }
  }
}
