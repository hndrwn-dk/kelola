import 'dart:convert';

import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/shell_quote.dart';

/// Remote sh for the exact-line grant file `kelola-web` (the per-action
/// `kelola-units` grant that also used it is gone, M52d). Reads the sudo
/// password on stdin (one line), copies [path]
/// (or starts it with [header]), appends each of [lines] only if it is not
/// already there, checks the merged file with `visudo -c -f`, installs it
/// root:root with [kelolaSudoersMode], greps every line back, then prints
/// [okMarker].
///
/// [lines] travel base64-encoded, never as shell text. [path], [header] and
/// [okMarker] are app constants. [preamble] (app-built shell, ending in a
/// newline) runs after the password is read and before anything is read or
/// written; empty when a grant needs none.
///
/// [lineConditions] (app-built shell tests, set by [preamble]) gate the
/// merge and confirm of the line at the same index; a null or missing entry
/// means always.
String buildSudoersGrantScript({
  required String path,
  required String header,
  required List<String> lines,
  required String okMarker,
  String preamble = '',
  List<String?> lineConditions = const [],
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
    final cond = i < lineConditions.length ? lineConditions[i] : null;
    final m =
        'grep -qxF -- "\$$v" "\$TMP" || '
        "printf '%s\\n' \"\$$v\" >> \"\$TMP\"";
    final c =
        "printf '%s\\n' \"\$SUDO_PASS\" | sudo -S -p '' "
        'grep -qxF -- "\$$v" $quoted';
    decode.write("$v=\$(printf '%s' '$b64' | base64 -d)\n");
    merge.write(cond == null ? '$m\n' : 'if $cond; then $m; fi\n');
    confirm.write(cond == null ? '$c\n' : 'if $cond; then $c; fi\n');
  }
  return '''
set -eu
IFS= read -r SUDO_PASS || true
TMP=\$(mktemp)
trap 'rm -f "\$TMP"' EXIT
$preamble$decode'''
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
