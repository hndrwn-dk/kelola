import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kelola/data/ssh/ssh_error_text.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/incident/incident_sheet.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/journal/journal_view.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/probes/container_logs_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/domain/probes/network_list_probe.dart';
import 'package:kelola/domain/probes/process_list_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/probes/unit_list_probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/data/llm/assist_service.dart';
import 'package:kelola/presentation/assist_flow.dart';
import 'package:kelola/presentation/host_session.dart';
import 'package:kelola/presentation/widgets/confirm_unit_action.dart';
import 'package:kelola/presentation/widgets/diagnostic_pack_sheet.dart';
import 'package:kelola/domain/llm/assist_request.dart';
import 'package:kelola/providers.dart';

Future<void> showIncidentSheet(
  BuildContext context, {
  required Host host,
  required IncidentSheetView view,
  void Function(IncidentAction action)? onAction,
  void Function(CorrelationLookUp lookUp)? onLookUp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return IncidentSheetPanel(
        host: host,
        view: view,
        onAction: onAction,
        onLookUp: onLookUp,
      );
    },
  );
}

Future<void> openHostIncident(
  BuildContext context,
  WidgetRef ref,
  Host host, {
  List<String>? failedUnitNames,
}) async {
  final repo = ref.read(hostRepositoryProvider);
  final store = ref.read(correlationStoreProvider);
  var names = failedUnitNames ?? const <String>[];
  if (names.isEmpty) {
    names = await repo.listFailedUnitNames(host.id);
  }
  if (names.isNotEmpty) {
    store.mergeFailedNames(host.id, names);
  }
  if (!context.mounted) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return _LiveIncidentSheet(host: host);
    },
  );
}

class IncidentSheetPanel extends StatelessWidget {
  const IncidentSheetPanel({
    super.key,
    required this.host,
    required this.view,
    this.onAction,
    this.onLookUp,
    this.onDiagnostic,
    this.onExplain,
    this.error,
  });

  final Host host;
  final IncidentSheetView view;
  final void Function(IncidentAction action)? onAction;
  final void Function(CorrelationLookUp lookUp)? onLookUp;
  final VoidCallback? onDiagnostic;
  final VoidCallback? onExplain;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.kc;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(KelolaRadii.lg),
          ),
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(
              'Incident',
              style: KelolaType.display(color: c.text, size: 16),
            ),
            Text(
              host.alias,
              style: KelolaType.mono(color: c.dim, size: 8.5, letterSpacing: 0.9),
            ),
            const SizedBox(height: 12),
            if (error != null) ...[
              KelolaError(message: error!, sudoUser: host.username),
              const SizedBox(height: 10),
            ],
            if (view.broken.isEmpty)
              Text(
                'Nothing broken in cache.',
                style: KelolaType.body(color: c.muted, size: 13),
              ),
            for (final obj in view.broken) ...[
              ServiceRow(
                risk: obj.kind == IncidentObjectKind.disk
                    ? RiskLevel.read
                    : RiskLevel.mutate,
                status: obj.kind == IncidentObjectKind.disk
                    ? HealthStatus.warning
                    : HealthStatus.failed,
                name: obj.name,
                meta: obj.summary,
              ),
              const SizedBox(height: 6),
            ],
            if (view.related.title.isNotEmpty || !view.related.cached) ...[
              const SizedBox(height: 6),
              Text(
                'RELATED',
                style: KelolaType.mono(
                  color: c.dim,
                  size: 8.5,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.read,
                name: view.related.title.isEmpty
                    ? 'Related'
                    : view.related.title,
                meta: view.related.meta,
                onTap: !view.related.cached && view.related.lookUp != null
                    ? () => onLookUp?.call(view.related.lookUp!)
                    : null,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'LOGS',
              style: KelolaType.mono(
                color: c.dim,
                size: 8.5,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(height: 6),
            if (view.logsInCache)
              for (final e in view.lines)
                JournalLogLine(
                  timestamp: _ts(e),
                  message: e.message,
                  kind: e.isError
                      ? JournalLineKind.error
                      : (e.isWarning
                          ? JournalLineKind.warning
                          : JournalLineKind.info),
                )
            else
              ServiceRow(
                risk: RiskLevel.read,
                name: 'Logs',
                meta: cacheMissLookUp,
                onTap: view.logsLookUp == null
                    ? null
                    : () => onLookUp?.call(view.logsLookUp!),
              ),
            if (view.actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final action in view.actions) ...[
                ServiceRow(
                  risk: action.risk,
                  name: action.label,
                  meta: view.focus?.name ?? host.alias,
                  onTap: onAction == null ? null : () => onAction!(action),
                ),
                const SizedBox(height: 6),
              ],
            ],
            if (onExplain != null) ...[
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.read,
                name: 'Explain',
                meta: 'assist · does not run',
                onTap: onExplain,
              ),
            ],
            if (onDiagnostic != null) ...[
              const SizedBox(height: 6),
              ServiceRow(
                risk: RiskLevel.read,
                name: 'Diagnostic pack',
                meta: 'preview then share',
                onTap: onDiagnostic,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _ts(JournalEntry e) {
    final t = e.timestamp;
    return t == null ? '' : journalClock(t);
  }
}

class _LiveIncidentSheet extends ConsumerStatefulWidget {
  const _LiveIncidentSheet({required this.host});

  final Host host;

  @override
  ConsumerState<_LiveIncidentSheet> createState() => _LiveIncidentSheetState();
}

class _LiveIncidentSheetState extends ConsumerState<_LiveIncidentSheet> {
  String? _error;

  IncidentSheetView get _view {
    return buildIncidentSheet(
      host: widget.host,
      cache: ref.read(correlationStoreProvider).get(widget.host.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IncidentSheetPanel(
      host: widget.host,
      view: _view,
      error: _error,
      onAction: _act,
      onLookUp: _lookUp,
      onDiagnostic: () => openDiagnosticPack(context, ref, widget.host),
      onExplain: () => _explain(),
    );
  }

  Future<void> _explain() async {
    final host = widget.host;
    final view = _view;
    final focus = view.focus;
    try {
      final settings = await requireAssistSettings(ref);
      if (!mounted) {
        return;
      }
      final journal = view.lines
          .map((e) => e.message)
          .where((m) => m.trim().isNotEmpty)
          .take(50)
          .join('\n');
      final hostnames = [host.alias, host.address];
      final usernames = [host.username];
      late final AssistRequest request;
      late final Future<String> Function(AssistService service) run;
      if (focus?.kind == IncidentObjectKind.disk) {
        request = AssistRequest(
          system:
              'Explain what is consuming disk space. '
              'Say what is conventionally safe to remove. Do not invent paths.',
          user: 'Disk attention on ${focus!.name}: ${focus.summary}\n$journal',
          hostnames: hostnames,
          usernames: usernames,
        );
        run = (s) => s.explainDisk(
              settings: settings,
              dfOutput: focus.summary,
              duOutput: journal,
              hostnames: hostnames,
              usernames: usernames,
            );
      } else {
        final unit = focus?.name ?? 'unknown.unit';
        request = AssistRequest(
          system:
              'Explain why this systemd unit failed in plain language. '
              'Suggest one next step. Do not invent facts absent from the input.',
          user: 'Unit: $unit\n\n--- journal ---\n$journal',
          hostnames: hostnames,
          usernames: usernames,
        );
        run = (s) => s.explainFailedUnit(
              settings: settings,
              unitName: unit,
              showOutput: focus?.summary ?? '',
              journal: journal,
              hostnames: hostnames,
              usernames: usernames,
            );
      }
      final text = await runAssistWithPreview(
        context: context,
        ref: ref,
        settings: settings,
        request: request,
        run: run,
      );
      if (!mounted || text == null) {
        return;
      }
      await showAssistResult(context, title: 'Explain', body: text);
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    }
  }

  Future<void> _lookUp(CorrelationLookUp lookUp) async {
    final host = widget.host;
    try {
      final facts =
          await ref.read(hostRepositoryProvider).facts(host.id) ??
              HostFacts.undiscovered;
      if (!mounted) {
        return;
      }
      switch (lookUp) {
        case CorrelationLookUp.journal:
          final unit = _view.focus?.name;
          await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            facts: facts,
            probe: JournalProbe(unit: unit, limit: 20),
          );
        case CorrelationLookUp.processes:
          await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            facts: facts,
            probe: const ProcessListProbe(),
          );
        case CorrelationLookUp.containerLogs:
          final cache = ref.read(correlationStoreProvider).get(host.id);
          final name = _view.focus?.name;
          for (final row in cache.containers) {
            if (row.title == name) {
              await runHostProbe(
                ref: ref,
                context: context,
                host: host,
                facts: facts,
                probe: ContainerLogsProbe(row),
              );
              break;
            }
          }
        case CorrelationLookUp.ports:
          await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            facts: facts,
            probe: const NetworkListProbe(),
          );
        case CorrelationLookUp.units:
          await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            facts: facts,
            probe: const UnitListProbe(),
          );
        case CorrelationLookUp.containers:
          await runHostProbe(
            ref: ref,
            context: context,
            host: host,
            facts: facts,
            probe: const ContainerListProbe(),
          );
      }
      if (mounted) {
        setState(() => _error = null);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    }
  }

  Future<void> _act(IncidentAction action) async {
    final host = widget.host;
    final focus = _view.focus;
    if (action.id == IncidentActionId.logs ||
        action.id == IncidentActionId.containerLogs) {
      await _lookUp(
        action.id == IncidentActionId.containerLogs
            ? CorrelationLookUp.containerLogs
            : CorrelationLookUp.journal,
      );
      return;
    }
    if (action.id != IncidentActionId.restart || focus == null) {
      return;
    }
    final ok = await confirmUnitAction(
      context,
      hostAlias: host.alias,
      unit: focus.name,
      verb: UnitVerb.restart,
    );
    if (!ok || !mounted) {
      return;
    }
    try {
      final facts =
          await ref.read(hostRepositoryProvider).facts(host.id) ??
              HostFacts.undiscovered;
      if (!mounted) {
        return;
      }
      await runHostProbe(
        ref: ref,
        context: context,
        host: host,
        facts: facts,
        probe: UnitActionProbe(unitName: focus.name, verb: UnitVerb.restart),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = describeSshError(e));
      }
    }
  }
}
