import 'dart:convert';

import 'package:kelola/domain/sudo/kelola_sudoers_spec.dart';
import 'package:kelola/domain/units/shell_quote.dart';

const sudoersInstallOkMarker = 'KELOLA_SUDOERS_OK';

/// Remote sh that reads the sudo password on stdin (one line), then installs
/// [content] to [kelolaSudoersPath]. Password must never appear in argv.
String buildSudoersInstallScript({required String content}) {
  final b64 = base64Encode(utf8.encode(content));
  assert(!b64.contains("'"), 'base64 must not contain single quotes');
  final path = shellSingleQuote(kelolaSudoersPath);
  final mode = shellSingleQuote(kelolaSudoersMode);
  return '''
set -eu
IFS= read -r SUDO_PASS || true
TMP=\$(mktemp)
trap 'rm -f "\$TMP"' EXIT
printf '%s' '$b64' | base64 -d > "\$TMP"
printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' visudo -c -f "\$TMP"
printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' install -o root -g root -m $mode "\$TMP" $path
printf '%s\\n' "\$SUDO_PASS" | sudo -S -p '' cat $path
printf '%s\\n' '$sudoersInstallOkMarker'
unset SUDO_PASS
''';
}

class SudoersInstallResult {
  const SudoersInstallResult({
    required this.ok,
    this.verifiedContent,
    this.errorSummary,
  });

  final bool ok;
  final String? verifiedContent;
  final String? errorSummary;
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
  final body = _extractSudoersBody(before).trimRight();
  final normalizedExpected = expectedContent.trimRight();
  if (body != normalizedExpected && !before.contains(normalizedExpected)) {
    return SudoersInstallResult(
      ok: false,
      errorSummary: 'verify mismatch',
      verifiedContent: body,
    );
  }
  return SudoersInstallResult(ok: true, verifiedContent: body);
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
