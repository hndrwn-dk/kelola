import 'package:kelola/domain/enrollment/key_install_script.dart';

class KeyInstallReport {
  const KeyInstallReport({
    required this.title,
    required this.body,
    required this.success,
  });

  final String title;
  final String body;
  final bool success;
}

KeyInstallReport buildKeyInstallReport({
  required KeyInstallAppendResult append,
  required bool verifyOk,
  required String fullLine,
}) {
  if (append.kind == KeyInstallAppendKind.failed) {
    return const KeyInstallReport(
      title: 'Key install failed',
      body:
          'Kelola could not append your public key. The file state on the server is unknown.',
      success: false,
    );
  }

  if (verifyOk) {
    return switch (append.kind) {
      KeyInstallAppendKind.appended => const KeyInstallReport(
          title: 'Key installed and verified',
          body: 'Your Kelola public key was appended and key-only authentication succeeded.',
          success: true,
        ),
      KeyInstallAppendKind.alreadyPresent => const KeyInstallReport(
          title: 'Key already present',
          body:
              'This key was already in authorized_keys and key-only authentication succeeded.',
          success: true,
        ),
      KeyInstallAppendKind.failed => throw StateError('unreachable'),
    };
  }

  final causes = _verifyFailCauses(append);
  final body = switch (append.kind) {
    KeyInstallAppendKind.appended =>
      'Kelola appended a line to authorized_keys, but key-only authentication failed.\n\n'
          'Line appended:\n$fullLine\n\n'
          'To undo, edit ~/.ssh/authorized_keys on the server and delete that line.\n\n'
          'Possible causes:\n$causes',
    KeyInstallAppendKind.alreadyPresent =>
      'A matching key body is already in authorized_keys, but key-only authentication failed.\n\n'
          'Possible causes:\n$causes',
    KeyInstallAppendKind.failed => throw StateError('unreachable'),
  };

  return KeyInstallReport(
    title: 'Key present but not verified',
    body: body,
    success: false,
  );
}

String _verifyFailCauses(KeyInstallAppendResult append) {
  final lines = <String>[];

  if (homeModeGroupOrWorldWritable(append.homeMode)) {
    lines.add(
      r'$HOME is group- or world-writable. sshd StrictModes will refuse key auth. '
      r'Kelola will not chmod $HOME.',
    );
  }

  if (append.createdSsh) {
    lines.add(
      'SELinux context may be wrong on RHEL-family hosts. '
      'Try restorecon -R ~/.ssh on the server.',
    );
  }

  lines.add(
    'sshd may read a different AuthorizedKeysFile (for example '
    '/etc/ssh/authorized_keys/%u). Kelola cannot read sshd_config as this user.',
  );

  if (append.kind == KeyInstallAppendKind.alreadyPresent) {
    lines.add(
      'The matching line may be commented out or restricted with options such as '
      'command= or from=.',
    );
  }

  return lines.map((line) => '- $line').join('\n');
}
