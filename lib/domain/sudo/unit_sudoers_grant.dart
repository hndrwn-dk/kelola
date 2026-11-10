import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/sudo_hint.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Rules for single named services. Enable Kelola sudo rewrites its own file,
/// so these live apart and survive it. Hosts without regex support (sudo-rs,
/// older sudo) have no other way to allow a service action.
const kelolaUnitSudoersPath = '/etc/sudoers.d/kelola-units';

const unitGrantOkMarker = 'KELOLA_UNIT_GRANT_OK';

const _lifecycleVerbs = {'start', 'stop', 'restart', 'reload'};

final _userName = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_.-]*$');

/// One passwordless action on one named service.
class UnitSudoersGrant {
  const UnitSudoersGrant._({
    required this.user,
    required this.verb,
    required this.unit,
  });

  final String user;
  final String verb;
  final String unit;

  /// Null unless every part is safe in a sudoers line. [unit] comes from the
  /// host's output, and `enable`, `disable` and `link` are refused because
  /// they act on unit files. Backslashes are refused too: systemd escapes such
  /// as `foo\x2dbar` need escaping again for sudoers, which is not worth
  /// trusting across sudo flavors for a rule this narrow.
  static UnitSudoersGrant? tryCreate({
    required String user,
    required String verb,
    required String unit,
  }) {
    if (!_userName.hasMatch(user) ||
        !_lifecycleVerbs.contains(verb) ||
        unit.contains(r'\') ||
        !isSudoersSafeUnitName(unit)) {
      return null;
    }
    return UnitSudoersGrant._(user: user, verb: verb, unit: unit);
  }

  /// The grant a failed service action asks for, or null if it was not one.
  static UnitSudoersGrant? fromHint(SudoHintContext hint, String user) {
    if (hint.kind != SudoHintKind.systemd) {
      return null;
    }
    final verb = hint.verb;
    final unit = hint.unit;
    if (verb == null || unit == null) {
      return null;
    }
    return tryCreate(user: user, verb: verb, unit: unit);
  }

  String get action => '$verb $unit';

  String get line =>
      '$user ALL=(root) NOPASSWD: /usr/bin/systemctl $verb ${sudoersEscape(unit)}';

  String get lineHash => sha256.convert(utf8.encode(line)).toString();
}

/// Remote sh that reads the sudo password on stdin (one line) and adds the
/// grant to [kelolaUnitSudoersPath], keeping the rules already there. The
/// merged file passes visudo before it replaces the old one.
String buildUnitGrantScript(UnitSudoersGrant grant) {
  return buildSudoersGrantScript(
    path: kelolaUnitSudoersPath,
    header: '# Kelola: one service action per line. Safe to edit.',
    lines: [grant.line],
    okMarker: unitGrantOkMarker,
  );
}

/// Remote sh shared by the exact-line grant files (`kelola-units`,
/// `kelola-web`). Reads the sudo password on stdin (one line), copies [path]
/// (or starts it with [header]), appends each of [lines] only if it is not
/// already there, checks the merged file with `visudo -c -f`, installs it
/// root:root with [kelolaSudoersMode], greps every line back, then prints
/// [okMarker].
///
/// [lines] travel base64-encoded, never as shell text. [path], [header] and
/// [okMarker] are app constants.
String buildSudoersGrantScript({
  required String path,
  required String header,
  required List<String> lines,
  required String okMarker,
}) {
  final quoted = shellSingleQuote(path);
  final mode = shellSingleQuote(kelolaSudoersMode);
  // `LINE` for the first, so a one-line grant reads exactly as PR #17's.
  String name(int i) => i == 0 ? 'LINE' : 'LINE$i';
  final decode = StringBuffer();
  final merge = StringBuffer();
  final confirm = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    final b64 = base64Encode(utf8.encode(lines[i]));
    final v = name(i);
    decode.write("$v=\$(printf '%s' '$b64' | base64 -d)\n");
    merge.write(
      'grep -qxF -- "\$$v" "\$TMP" || '
      "printf '%s\\n' \"\$$v\" >> \"\$TMP\"\n",
    );
    confirm.write(
      "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p '' "
      'grep -qxF -- "\$$v" $quoted\n',
    );
  }
  return '''
set -eu
IFS= read -r SUDO_PASS || true
TMP=\$(mktemp)
trap 'rm -f "\$TMP"' EXIT
$decode'''
      '''
if printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' test -f $quoted; then
  printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' cat $quoted > "\$TMP"
else
  printf '%s\\n' '$header' > "\$TMP"
fi
$merge'''
      '''
printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' visudo -c -f "\$TMP"
printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' install -o root -g root -m $mode "\$TMP" $quoted
$confirm'''
      '''
printf '%s\\n' '$okMarker'
unset SUDO_PASS
''';
}
