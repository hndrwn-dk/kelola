import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/probes/compose_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

Future<bool> confirmComposeAction(
  BuildContext context, {
  required String hostAlias,
  required String project,
  required ComposeVerb verb,
  required bool lockout,
}) async {
  final title = switch (verb) {
    ComposeVerb.up => 'Start $project?',
    ComposeVerb.down => 'Take down $project?',
    ComposeVerb.restart => 'Restart $project?',
    ComposeVerb.pull => 'Pull $project?',
  };
  if (verb == ComposeVerb.down || lockout) {
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
            consequence: lockout
                ? 'This will end your session and may make $hostAlias unreachable.'
                : 'This stops every service in $project on $hostAlias.',
            warning: lockout
                ? 'You will lose access immediately. Recovery needs physical or console access to the machine.'
                : 'Type $project to confirm. This cannot be undone from Kelola.',
            confirmToken: project,
            onConfirmed: () => confirmed = true,
          ),
        );
      },
    );
    return confirmed;
  }

  return showMutateConfirm(
    context,
    title: title,
    body: 'This changes compose project $project on $hostAlias.',
    confirmLabel: verb.name,
  );
}

RiskLevel composeActionRisk(ComposeVerb verb, {required bool lockout}) {
  if (verb == ComposeVerb.down || lockout) {
    return RiskLevel.destructive;
  }
  return RiskLevel.mutate;
}
