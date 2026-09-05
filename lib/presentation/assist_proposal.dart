import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/llm/assist_context.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/domain/llm/catalog.dart';
import 'package:kelola/domain/llm/propose.dart';
import 'package:kelola/domain/probes/df_pt_probe.dart';
import 'package:kelola/domain/probes/disk_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/probes/unit_list_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';

Future<AssistContext> loadAssistContext({
  required WidgetRef ref,
  required BuildContext context,
  required Host host,
}) async {
  final units = await runHostProbe(
    ref: ref,
    context: context,
    host: host,
    probe: const UnitListProbe(),
  );
  final mounts = await runHostProbe(
    ref: ref,
    context: context,
    host: host,
    probe: const DiskProbe(),
  );
  return AssistContext(
    unitNames: units.units.map((u) => u.name).toList(growable: false),
    paths: mounts.map((DiskMount m) => m.mounted).toList(growable: false),
    hostAlias: host.alias,
  );
}

AssistRequest intentAssistRequest({
  required String intent,
  required AssistContext context,
  required List<String> hostnames,
  required List<String> usernames,
}) {
  return AssistRequest(
    system:
        'Map the user intent to one catalog action. '
        'Only use units/paths listed in context. '
        '${catalogPromptBlock()}\n'
        'Context units: ${context.unitNames.join(', ')}\n'
        'Context paths: ${context.paths.join(', ')}',
    user: intent,
    hostnames: hostnames,
    usernames: usernames,
  );
}

Probe? probeForProposal(ProbeProposal proposal) {
  if (!proposal.available || proposal.probeKind == null) {
    return null;
  }
  switch (proposal.probeKind) {
    case 'unit_restart':
      return UnitActionProbe(
        unitName: proposal.unit!,
        verb: UnitVerb.restart,
      );
    case 'unit_start':
      return UnitActionProbe(
        unitName: proposal.unit!,
        verb: UnitVerb.start,
      );
    case 'unit_stop':
      return UnitActionProbe(
        unitName: proposal.unit!,
        verb: UnitVerb.stop,
      );
    case 'unit_enable':
      return UnitActionProbe(
        unitName: proposal.unit!,
        verb: UnitVerb.enable,
      );
    case 'unit_disable':
      return UnitActionProbe(
        unitName: proposal.unit!,
        verb: UnitVerb.disable,
      );
    case 'df_pt':
      return const DfPtProbe();
    default:
      return null;
  }
}

UnitVerb? unitVerbForProposal(ProbeProposal proposal) {
  switch (proposal.probeKind) {
    case 'unit_restart':
      return UnitVerb.restart;
    case 'unit_start':
      return UnitVerb.start;
    case 'unit_stop':
      return UnitVerb.stop;
    case 'unit_enable':
      return UnitVerb.enable;
    case 'unit_disable':
      return UnitVerb.disable;
    default:
      return null;
  }
}

Future<void> showAssistProposalSheet(
  BuildContext context, {
  required Host host,
  required ProbeProposal proposal,
  required Future<void> Function(ProbeProposal proposal) onRun,
}) {
  final c = context.kc;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return KelolaSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 0),
          child: RiskBand(
            risk: proposal.available ? proposal.risk : RiskLevel.read,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Proposal',
                  style: KelolaType.display(color: c.text, size: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  proposal.available
                      ? '${proposal.label} · ${proposal.unit ?? proposal.path ?? ''}'
                          .trim()
                      : proposal.message,
                  style: KelolaType.body(color: c.text, size: 13),
                ),
                const SizedBox(height: 12),
                if (proposal.available)
                  ServiceRow(
                    risk: proposal.risk,
                    name: 'Run',
                    meta: 'confirm then probe',
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      await onRun(proposal);
                    },
                  ),
                if (proposal.available) const SizedBox(height: 6),
                ServiceRow(
                  risk: RiskLevel.read,
                  name: 'Close',
                  meta: proposal.available
                      ? 'assist only · nothing ran yet'
                      : 'assist only · nothing ran',
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Future<void> runProposedProbe({
  required BuildContext context,
  required WidgetRef ref,
  required Host host,
  required ProbeProposal proposal,
}) async {
  final probe = probeForProposal(proposal);
  if (probe == null) {
    return;
  }
  final verb = unitVerbForProposal(proposal);
  if (verb != null && proposal.unit != null) {
    final ok = await confirmUnitAction(
      context,
      hostAlias: host.alias,
      unit: proposal.unit!,
      verb: verb,
    );
    if (!ok) {
      return;
    }
  }
  await runHostProbe(
    ref: ref,
    context: context,
    host: host,
    probe: probe,
  );
}
