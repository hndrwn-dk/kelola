import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo/web_sudoers_grant.dart';
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

/// Printed by the install script, with the unit, the failing path (each
/// base64) and a [WebConfigRefusalReason] name, for each web server unit
/// whose lifecycle lines were left out ([WebUnitGate]).
const sudoersUnitConfigMarker = 'KELOLA_UNIT_CONFIG';

/// ERE (for `grep -Ex`) for the old per-action grant's lines for [user] on
/// web server [unit], written either as `nginx` or `nginx.service`.
String webUnitGrantLineRegex(String user, String unit) {
  String ere(String s) =>
      s.replaceAllMapped(RegExp(r'[.^$*+?()\[\]{}|\\]'), (m) => '\\${m[0]}');
  final base = unit.endsWith('.service')
      ? unit.substring(0, unit.length - '.service'.length)
      : unit;
  return '${ere(user)} '
      r'ALL=\(root\) NOPASSWD: /usr/bin/systemctl '
      '(start|stop|restart|reload) ${ere(base)}(\\.service)?';
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
///
/// [webUnitGates] (needs [user]): web server units whose lifecycle lines are
/// kept only when the server config is root-controlled
/// ([webUnitConfigGateShell], run as the login before visudo). A unit that
/// fails has its exact lines cut from the new file and its old
/// `kelola-units` lines left behind (not moved; the file is still retired),
/// and prints [sudoersUnitConfigMarker]. Other lines are unaffected. Empty
/// (every host without a web server unit): the script is unchanged.
///
/// [trustOwners] and [configPrefix] exist for tests only (see
/// [buildWebGrantScript]).
String buildSudoersInstallScript({
  required String content,
  String? user,
  bool retireUnits = false,
  bool journalGroup = false,
  List<WebUnitGate> webUnitGates = const [],
  @visibleForTesting List<String> trustOwners = const ['root'],
  @visibleForTesting String configPrefix = '',
}) {
  final b64 = base64Encode(utf8.encode(content));
  assert(!b64.contains("'"), 'base64 must not contain single quotes');
  final path = shellSingleQuote(kelolaSudoersPath);
  final mode = shellSingleQuote(kelolaSudoersMode);
  final login = user != null && isSudoersSafeLogin(user) ? user : null;
  const sudo = "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p ''";
  final units = shellSingleQuote(kelolaUnitSudoersPath);
  final gates = login == null ? const <WebUnitGate>[] : webUnitGates;
  final contentLines = content.split('\n').toSet();
  final gateShell = StringBuffer();
  if (gates.isNotEmpty) {
    gateShell.write(
      webUnitConfigGateShell(
        gates,
        sudoersUnitConfigMarker,
        trustOwners,
        configPrefix,
      ),
    );
    for (final (j, g) in gates.indexed) {
      for (final l in webUnitLines(login!, g.unit)) {
        if (!contentLines.contains(l)) continue;
        final lb = base64Encode(utf8.encode(l));
        gateShell.writeln(
          'if [ "\$KELOLA_U$j" != 1 ]; then '
          "L=\$(printf '%s' '$lb' | base64 -d); "
          '{ grep -vxF -- "\$L" "\$TMP" || true; } > "\$CUT"; '
          'cat "\$CUT" > "\$TMP"; fi',
        );
      }
    }
  }
  // A folded line of a refused unit is dropped, not moved.
  final skip = StringBuffer();
  for (final (j, g) in gates.indexed) {
    skip.writeln(
      '    if [ "\$KELOLA_U$j" != 1 ] && printf \'%s\\n\' "\$l" | '
      'grep -Eqx -- ${shellSingleQuote(webUnitGrantLineRegex(login!, g.unit))}; '
      'then continue; fi',
    );
  }
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
$skip      grep -qxF -- "\$l" "\$TMP" || printf '%s\\n' "\$l" >> "\$TMP"
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
  final temps = gates.isEmpty
      ? '''
OLD=\$(mktemp)
trap 'rm -f "\$TMP" "\$OLD"' EXIT
'''
      : '''
OLD=\$(mktemp)
CUT=\$(mktemp)
trap 'rm -f "\$TMP" "\$OLD" "\$CUT"' EXIT
''';
  return '''
set -eu
IFS= read -r SUDO_PASS || true
TMP=\$(mktemp)
$temps'''
      '''
printf '%s' '$b64' | base64 -d > "\$TMP"
$gateShell$fold$sudo visudo -c -f "\$TMP"
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
    this.unitRefusals = const [],
  });

  final bool ok;
  final String? verifiedContent;
  final String? errorSummary;
  final JournalGroupOutcome journalGroup;

  /// [kelolaUnitSudoersPath] was folded into the main file and removed.
  final bool unitsRetired;

  /// Web server units whose lifecycle lines the host left out.
  final List<WebUnitRefusal> unitRefusals;
}

SudoersInstallResult parseSudoersInstallOutput({
  required String stdout,
  required String stderr,
  required int exitCode,
  required String expectedContent,
  String? user,
  List<WebUnitGate> webUnitGates = const [],
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
  final refusals = user == null
      ? const <WebUnitRefusal>[]
      : _unitRefusals(before, webUnitGates);
  // A refused unit's lines were cut on the host, so they are not expected.
  final cut = {for (final r in refusals) ...webUnitLines(user!, r.unit)};
  final normalizedExpected = [
    for (final l in expectedContent.split('\n'))
      if (!cut.contains(l)) l,
  ].join('\n').trimRight();
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
    unitRefusals: refusals,
  );
}

/// Each [sudoersUnitConfigMarker] line in [out] for a unit in [gates], once.
/// Host text is only displayed ([webGrantConfigRefusal] checks the path).
List<WebUnitRefusal> _unitRefusals(String out, List<WebUnitGate> gates) {
  final res = <WebUnitRefusal>[];
  for (final line in const LineSplitter().convert(out)) {
    if (!line.startsWith('$sudoersUnitConfigMarker ')) continue;
    final words = line.substring(sudoersUnitConfigMarker.length + 1).split(' ');
    if (words.length != 3) continue;
    String unit;
    try {
      unit = utf8.decode(base64Decode(words[0]));
    } on FormatException {
      continue;
    }
    if (!gates.any((g) => g.unit == unit)) continue;
    if (res.any((r) => r.unit == unit)) continue;
    // `-`: the gate had no server binary to ask ([webUnitConfigGateShell]).
    final refusal = words[1] == '-'
        ? const WebGrantConfigRefusal(
            path: 'the server binary',
            reason: WebConfigRefusalReason.unreadable,
          )
        : webGrantConfigRefusal(
            '$webGrantConfigMarker ${words[1]} ${words[2]}',
          );
    if (refusal == null) continue;
    res.add(WebUnitRefusal(unit: unit, refusal: refusal));
  }
  return res;
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
