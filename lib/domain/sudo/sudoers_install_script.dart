import 'dart:convert';

import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/shell_quote.dart';

const sudoersInstallOkMarker = 'KELOLA_SUDOERS_OK';

/// M52d: printed after [sudoersInstallOkMarker] with how the login's
/// `systemd-journal` membership ended: `member`, `added`, `failed` or
/// `nogroup`.
const sudoersJournalGroupMarker = 'KELOLA_JOURNAL_GROUP=';

/// M52d: printed after [sudoersInstallOkMarker] once `kelola-units` was
/// folded into [kelolaSudoersPath] and removed.
const sudoersUnitsRetiredMarker = 'KELOLA_UNITS_RETIRED';

/// The file the old per-action service grant wrote. M52d folds its lines for
/// this login into [kelolaSudoersPath] and removes it.
const kelolaUnitSudoersPath = '/etc/sudoers.d/kelola-units';

/// The group whose members read every journal without sudo.
const kelolaJournalGroup = 'systemd-journal';

final _loginName = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]*$');

/// Whether [user] can be written into the install script and a sudoers line.
bool isSudoersSafeLogin(String user) => _loginName.hasMatch(user);

/// ERE (for `grep -Ex`) that matches one line the old per-action grant wrote
/// for [user]: one lifecycle verb on one unit, `:` escaped. Nothing else in
/// `kelola-units` is moved.
String unitGrantLineRegex(String user) {
  final u = user.replaceAll('.', r'\.');
  return '$u '
      r'ALL=\(root\) NOPASSWD: /usr/bin/systemctl '
      r'(start|stop|restart|reload) [a-zA-Z0-9]([a-zA-Z0-9_.@-]|\\:)*';
}

/// Remote sh that reads the sudo password on stdin (one line), then installs
/// [content] to [kelolaSudoersPath]. Password must never appear in argv.
///
/// With [user] set (M52d, checked by [isSudoersSafeLogin]):
/// - [retireUnits] copies each line of [kelolaUnitSudoersPath] that the old
///   service grant wrote for [user] into the new file before visudo checks
///   it, and removes [kelolaUnitSudoersPath] after the install only when
///   every rule in it was moved. Anything else there keeps the file.
/// - [journalGroup] adds [user] to [kelolaJournalGroup] when the host has
///   that group and [user] is not in it yet.
///
/// Both run after the main file is installed or never; neither can fail the
/// install. Their results follow [sudoersInstallOkMarker].
String buildSudoersInstallScript({
  required String content,
  String? user,
  bool retireUnits = false,
  bool journalGroup = false,
}) {
  final b64 = base64Encode(utf8.encode(content));
  assert(!b64.contains("'"), 'base64 must not contain single quotes');
  final path = shellSingleQuote(kelolaSudoersPath);
  final mode = shellSingleQuote(kelolaSudoersMode);
  final login = user != null && isSudoersSafeLogin(user) ? user : null;
  const sudo = "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p ''";
  final units = shellSingleQuote(kelolaUnitSudoersPath);
  final fold = login == null || !retireUnits
      ? ''
      : '''
RETIRE=0
if $sudo test -f $units; then
  $sudo cat $units > "\$OLD"
  RETIRE=1
  while IFS= read -r l || [ -n "\$l" ]; do
    case "\$l" in ''|'#'*) continue ;; esac
    if printf '%s\\n' "\$l" | grep -Eqx -- ${shellSingleQuote(unitGrantLineRegex(login))}; then
      grep -qxF -- "\$l" "\$TMP" || printf '%s\\n' "\$l" >> "\$TMP"
    else
      RETIRE=0
    fi
  done < "\$OLD"
fi
''';
  final retire = fold.isEmpty
      ? ''
      : '''
if [ "\$RETIRE" = 1 ] && $sudo rm -f -- $units; then
  printf '%s\\n' '$sudoersUnitsRetiredMarker'
fi
''';
  final group = login == null || !journalGroup
      ? ''
      : '''
if ! getent group $kelolaJournalGroup >/dev/null 2>&1; then
  printf '%s\\n' '${sudoersJournalGroupMarker}nogroup'
elif id -nG ${shellSingleQuote(login)} 2>/dev/null | tr ' ' '\\n' | grep -qx $kelolaJournalGroup; then
  printf '%s\\n' '${sudoersJournalGroupMarker}member'
elif $sudo usermod -aG $kelolaJournalGroup ${shellSingleQuote(login)}; then
  printf '%s\\n' '${sudoersJournalGroupMarker}added'
else
  printf '%s\\n' '${sudoersJournalGroupMarker}failed'
fi
''';
  return '''
set -eu
IFS= read -r SUDO_PASS || true
TMP=\$(mktemp)
OLD=\$(mktemp)
trap 'rm -f "\$TMP" "\$OLD"' EXIT
printf '%s' '$b64' | base64 -d > "\$TMP"
$fold$sudo visudo -c -f "\$TMP"
$sudo install -o root -g root -m $mode "\$TMP" $path
$sudo cat $path
printf '%s\\n' '$sudoersInstallOkMarker'
$retire$group'''
      'unset SUDO_PASS\n';
}

/// How the login's [kelolaJournalGroup] membership ended (M52d).
enum JournalGroupOutcome { notAsked, member, added, failed, noGroup }

class SudoersInstallResult {
  const SudoersInstallResult({
    required this.ok,
    this.verifiedContent,
    this.errorSummary,
    this.journalGroup = JournalGroupOutcome.notAsked,
    this.unitsRetired = false,
  });

  final bool ok;
  final String? verifiedContent;
  final String? errorSummary;
  final JournalGroupOutcome journalGroup;

  /// [kelolaUnitSudoersPath] was folded into the main file and removed.
  final bool unitsRetired;
}

SudoersInstallResult parseSudoersInstallOutput({
  required String stdout,
  required String stderr,
  required int exitCode,
  required String expectedContent,
}) {
  if (exitCode != 0) {
    final err = stderr.trim().isEmpty ? 'exit $exitCode' : stderr.trim();
    return SudoersInstallResult(ok: false, errorSummary: err);
  }
  if (!stdout.contains(sudoersInstallOkMarker)) {
    return const SudoersInstallResult(
      ok: false,
      errorSummary: 'install did not confirm',
    );
  }
  final markerAt = stdout.indexOf(sudoersInstallOkMarker);
  final before = stdout.substring(0, markerAt);
  final after = stdout.substring(markerAt + sudoersInstallOkMarker.length);
  final journalGroup = _journalGroupOutcome(after);
  final unitsRetired = after
      .split('\n')
      .map((l) => l.trim())
      .contains(sudoersUnitsRetiredMarker);
  final body = _extractSudoersBody(before).trimRight();
  final normalizedExpected = expectedContent.trimRight();
  // Lines moved from kelola-units follow the expected content.
  if (body != normalizedExpected && !before.contains(normalizedExpected)) {
    return SudoersInstallResult(
      ok: false,
      errorSummary: 'verify mismatch',
      verifiedContent: body,
    );
  }
  return SudoersInstallResult(
    ok: true,
    verifiedContent: body,
    journalGroup: journalGroup,
    unitsRetired: unitsRetired,
  );
}

JournalGroupOutcome _journalGroupOutcome(String after) {
  for (final line in after.split('\n')) {
    final l = line.trim();
    if (!l.startsWith(sudoersJournalGroupMarker)) continue;
    return switch (l.substring(sudoersJournalGroupMarker.length)) {
      'member' => JournalGroupOutcome.member,
      'added' => JournalGroupOutcome.added,
      'nogroup' => JournalGroupOutcome.noGroup,
      _ => JournalGroupOutcome.failed,
    };
  }
  return JournalGroupOutcome.notAsked;
}

String _extractSudoersBody(String before) {
  final lines = before.split('\n');
  final start = lines.indexWhere(
    (l) => l.startsWith('#') || l.contains(' ALL='),
  );
  if (start < 0) {
    return before.trimRight();
  }
  return lines.sublist(start).join('\n').trimRight();
}
