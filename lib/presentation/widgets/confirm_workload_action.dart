import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/workload_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

Future<bool> confirmWorkloadAction(
  BuildContext context, {
  required String hostAlias,
  required K8sWorkload workload,
  required WorkloadVerb verb,
  int? replicas,
}) async {
  final title = switch (verb) {
    WorkloadVerb.restart => 'Restart ${workload.title}?',
    WorkloadVerb.scale => 'Scale ${workload.title} to ${replicas ?? workload.desired}?',
    WorkloadVerb.delete => 'Delete ${workload.title}?',
  };
  if (verb == WorkloadVerb.delete) {
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
            consequence:
                'This deletes ${workload.title} on $hostAlias. Controllers may recreate owned pods.',
            warning: 'Type ${workload.title} to confirm. This cannot be undone from Kelola.',
            confirmToken: workload.title,
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
    body: verb == WorkloadVerb.scale
        ? 'This sets replicas to ${replicas ?? workload.desired} on $hostAlias.'
        : 'This rolls the workload on $hostAlias.',
    confirmLabel: verb.name,
  );
}

RiskLevel workloadActionRisk(WorkloadVerb verb) {
  return verb == WorkloadVerb.delete ? RiskLevel.destructive : RiskLevel.mutate;
}
