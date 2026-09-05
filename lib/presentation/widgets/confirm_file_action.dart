import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/files/sftp_lockout.dart';
import 'package:kelola/domain/files/sftp_path.dart';

Future<bool> confirmFileDelete(
  BuildContext context, {
  required String hostAlias,
  required String path,
}) {
  final name = sftpBasename(path);
  return _sheet(
    context,
    title: 'Delete $name?',
    consequence: isSshLockoutPath(path)
        ? 'This will end your session and may make $hostAlias unreachable.'
        : 'This deletes $name on $hostAlias.',
    warning: isSshLockoutPath(path)
        ? 'You will lose access immediately. Recovery needs physical or console access to the machine.'
        : 'This cannot be undone from Kelola.',
    token: name,
  );
}

Future<bool> confirmFileMutate(
  BuildContext context, {
  required String hostAlias,
  required String path,
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  if (isSshLockoutPath(path)) {
    return _sheet(
      context,
      title: title,
      consequence:
          'This will end your session and may make $hostAlias unreachable.',
      warning:
          'You will lose access immediately. Recovery needs physical or console access to the machine.',
      token: sftpBasename(path),
    );
  }
  return showMutateConfirm(
    context,
    title: title,
    body: body,
    confirmLabel: confirmLabel,
  );
}

Future<bool> confirmFileDiff(BuildContext context, String diff) async {
  final c = context.kc;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        child: RiskBand(
          risk: RiskLevel.mutate,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review changes',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      diff,
                      style: KelolaType.mono(color: c.text, size: 11),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(
                          'Dismiss',
                          style: KelolaType.display(color: c.muted, size: 13),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(
                          'Save',
                          style: KelolaType.display(color: c.amber, size: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return ok == true;
}

Future<bool> _sheet(
  BuildContext context, {
  required String title,
  required String consequence,
  required String warning,
  required String token,
}) async {
  var confirmed = false;
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return KelolaSheet(
          child: DestructiveConfirmSheet(
          title: title,
          consequence: consequence,
          warning: warning,
          confirmToken: token,
          onConfirmed: () => confirmed = true,
        ),
      );
    },
  );
  return confirmed;
}
