import 'dart:convert';

enum KeyInstallAppendKind { appended, alreadyPresent, failed }

class KeyInstallAppendResult {
  const KeyInstallAppendResult({
    required this.kind,
    required this.homeMode,
    required this.createdSsh,
  });

  final KeyInstallAppendKind kind;
  final String homeMode;
  final bool createdSsh;
}

void assertSafeKeyInstallToken(String value, {required String label}) {
  if (value.contains("'") ||
      value.contains('"') ||
      value.contains('\\') ||
      value.contains('\n') ||
      RegExp(r'\s').hasMatch(value)) {
    throw ArgumentError('unsafe $label token');
  }
}

void _validateKeyInstallInputs(String keyBody, String fullLine) {
  assertSafeKeyInstallToken(keyBody, label: 'body');
  final parts = fullLine.split(RegExp(r'\s+'));
  if (parts.length < 3) {
    throw ArgumentError('fullLine must include key type, body, and comment');
  }
  final comment = parts.sublist(2).join(' ');
  assertSafeKeyInstallToken(comment, label: 'comment');
}

String buildKeyInstallScript({
  required String keyBody,
  required String fullLine,
}) {
  _validateKeyInstallInputs(keyBody, fullLine);
  return '''
set -eu
AK="\$HOME/.ssh/authorized_keys"
KEY_BODY='$keyBody'
LINE='$fullLine'
CREATED_SSH=0

# StrictModes cares about \$HOME as well as ~/.ssh. Record only — never chmod \$HOME.
HOME_MODE="\$(ls -ld "\$HOME" | awk '{print \$1}')"

if [ ! -d "\$HOME/.ssh" ]; then
  mkdir -m 700 "\$HOME/.ssh"
  CREATED_SSH=1
fi

if [ ! -f "\$AK" ]; then
  umask 077
  : >> "\$AK"
  chmod 600 "\$AK"
fi

if [ "\$CREATED_SSH" -eq 1 ]; then
  if command -v restorecon >/dev/null 2>&1; then
    restorecon -R "\$HOME/.ssh" 2>/dev/null || true
  fi
fi

if [ -s "\$AK" ]; then
  last="\$(tail -c 1 "\$AK" | wc -l)"
  if [ "\$last" -eq 0 ]; then
    printf '\\n' >> "\$AK"
  fi
fi

if grep -F -- "\$KEY_BODY" "\$AK" >/dev/null 2>&1; then
  printf 'HOME_MODE=%s\\nCREATED_SSH=%s\\n' "\$HOME_MODE" "\$CREATED_SSH"
  exit 3
fi

printf '%s\\n' "\$LINE" >> "\$AK"
printf 'HOME_MODE=%s\\nCREATED_SSH=%s\\n' "\$HOME_MODE" "\$CREATED_SSH"
exit 0
''';
}

String buildKeyInstallRemoteCommand({
  required String keyBody,
  required String fullLine,
}) {
  final script = buildKeyInstallScript(keyBody: keyBody, fullLine: fullLine);
  final b64 = base64Encode(utf8.encode(script));
  assert(!b64.contains("'"), 'base64 must not contain single quotes');
  return "printf '%s' '$b64' | base64 -d | sh -s";
}

bool homeModeGroupOrWorldWritable(String homeMode) {
  var mode = homeMode;
  while (mode.endsWith('.') || mode.endsWith('+')) {
    mode = mode.substring(0, mode.length - 1);
  }
  if (mode.length < 10) {
    return false;
  }
  return mode[5] == 'w' || mode[8] == 'w';
}

KeyInstallAppendResult parseKeyInstallAppendResult({
  required int exitCode,
  required String stdout,
}) {
  var homeMode = '';
  var createdSsh = false;

  for (final line in stdout.split('\n')) {
    if (line.startsWith('HOME_MODE=')) {
      homeMode = line.substring('HOME_MODE='.length);
    } else if (line.startsWith('CREATED_SSH=')) {
      createdSsh = line.substring('CREATED_SSH='.length) == '1';
    }
  }

  final kind = switch (exitCode) {
    0 => KeyInstallAppendKind.appended,
    3 => KeyInstallAppendKind.alreadyPresent,
    _ => KeyInstallAppendKind.failed,
  };

  return KeyInstallAppendResult(
    kind: kind,
    homeMode: homeMode,
    createdSsh: createdSsh,
  );
}
