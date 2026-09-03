import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/containers/container_lockout.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

Future<bool> confirmContainerAction(
  BuildContext context, {
  required String hostAlias,
  required ContainerRow row,
  required ContainerVerb verb,
  int sshPort = 22,
}) async {
  final title =
      '${verb.name[0].toUpperCase()}${verb.name.substring(1)} ${row.title}?';
  final lockout = isLockoutContainerAction(verb.name, row, sshPort: sshPort);
  if (verb == ContainerVerb.remove || lockout) {
    final token = row.title;
    final consequence = lockout
        ? 'This will end your session and may make $hostAlias unreachable.'
        : 'This removes ${row.title} on $hostAlias.';
    final warning = lockout
        ? 'You will lose access immediately. Recovery needs physical or console access to the machine.'
        : 'This cannot be undone from Kelola.';
    return _sheet(
      context,
      title: title,
      consequence: consequence,
      warning: warning,
      token: token,
    );
  }

  return showMutateConfirm(
    context,
    title: title,
    body: 'This changes container state on $hostAlias.',
    confirmLabel: verb.name,
  );
}

Future<bool> confirmContainerPrune(
  BuildContext context, {
  required String hostAlias,
  required String reclaimableLabel,
}) {
  final size = reclaimableLabel.trim().isEmpty ? 'unknown size' : reclaimableLabel;
  return _sheet(
    context,
    title: 'Prune unused images?',
    consequence: 'This deletes dangling images on $hostAlias and reclaims $size.',
    warning:
        'Never auto-pruned. Type $hostAlias to confirm. Image data cannot be restored from Kelola.',
    token: hostAlias,
  );
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
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
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

RiskLevel containerActionRisk(ContainerVerb verb, ContainerRow row,
    {int sshPort = 22}) {
  return ContainerActionProbe(row: row, verb: verb, sshPort: sshPort).risk;
}
