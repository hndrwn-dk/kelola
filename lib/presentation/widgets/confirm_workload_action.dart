import 'package:flutter/material.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
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

Future<bool> confirmWorkloadYamlApply(
  BuildContext context, {
  required String hostAlias,
  required K8sWorkload workload,
  required String diff,
}) async {
  final c = context.kc;
  final reviewed = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: c.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(KelolaRadii.lg),
      ),
      side: BorderSide(color: c.line),
    ),
    builder: (ctx) {
      return KelolaSheet(
        child: SizedBox(
          height: kelolaSheetBodyHeight(ctx),
          child: ListView(
            padding: kelolaScrollPadding(ctx, top: 16),
            children: [
              Text(
                'Server diff',
                style: KelolaType.display(color: c.text, size: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'kubectl diff for ${workload.title} on $hostAlias.',
                style: KelolaType.body(color: c.muted, size: 13),
              ),
              const SizedBox(height: 12),
              RiskBand(
                risk: RiskLevel.mutate,
                child: SelectableText(
                  diff,
                  style: KelolaType.mono(color: c.muted, size: 10.5),
                ),
              ),
              const SizedBox(height: 12),
              ServiceRow(
                risk: RiskLevel.destructive,
                name: 'Continue apply',
                meta: workload.title,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (reviewed != true || !context.mounted) {
    return false;
  }
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
          title: 'Apply ${workload.title}?',
          consequence:
              'This writes ${workload.title} on $hostAlias through kubectl apply.',
          warning: 'Type ${workload.title} to confirm. This cannot be undone from Kelola.',
          confirmToken: workload.title,
          onConfirmed: () => confirmed = true,
        ),
      );
    },
  );
  return confirmed;
}
