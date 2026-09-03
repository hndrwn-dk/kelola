import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/incident/correlation.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

enum IncidentObjectKind { unit, container, disk }

enum IncidentActionId { restart, logs, containerLogs }

class IncidentObject {
  const IncidentObject({
    required this.kind,
    required this.name,
    required this.summary,
  });

  final IncidentObjectKind kind;
  final String name;
  final String summary;
}

class IncidentAction {
  const IncidentAction({
    required this.id,
    required this.label,
    required this.risk,
  });

  final IncidentActionId id;
  final String label;
  final RiskLevel risk;
}

class IncidentSheetView {
  const IncidentSheetView({
    required this.broken,
    required this.lines,
    required this.logsInCache,
    required this.related,
    required this.actions,
    this.blocking = false,
    this.logsLookUp,
    this.focus,
  });

  final List<IncidentObject> broken;
  final List<JournalEntry> lines;
  final bool logsInCache;
  final RelatedEntity related;
  final List<IncidentAction> actions;
  final bool blocking;
  final CorrelationLookUp? logsLookUp;
  final IncidentObject? focus;
}

IncidentSheetView buildIncidentSheet({
  required Host host,
  required CorrelationSnapshot cache,
}) {
  final broken = <IncidentObject>[
    for (final name in cache.failedUnitNames)
      if (name.trim().isNotEmpty)
        IncidentObject(
          kind: IncidentObjectKind.unit,
          name: name.trim(),
          summary: 'failed',
        ),
    if ((host.diskRootPercent ?? 0) >= 90)
      IncidentObject(
        kind: IncidentObjectKind.disk,
        name: '/',
        summary: 'disk ${host.diskRootPercent}%',
      ),
    for (final row in cache.containers)
      if (isRestartingContainer(row))
        IncidentObject(
          kind: IncidentObjectKind.container,
          name: row.title,
          summary: 'restarting',
        ),
  ];
  if (broken.isEmpty && (host.failedUnitCount ?? 0) > 0) {
    broken.add(
      IncidentObject(
        kind: IncidentObjectKind.unit,
        name: '${host.failedUnitCount} units failed',
        summary: 'not in cache — look up',
      ),
    );
  }

  final focus = broken.isEmpty ? null : broken.first;
  var related = RelatedEntity.empty;
  var lines = const <JournalEntry>[];
  var logsInCache = false;
  CorrelationLookUp? logsLookUp;
  var actions = const <IncidentAction>[];

  if (focus?.kind == IncidentObjectKind.unit) {
    final unit = focus!.name;
    final named = cache.failedUnitNames.contains(unit) ||
        cache.units.any((u) => u.name == unit);
    if (!named) {
      related = RelatedEntity.miss(
        lookUp: CorrelationLookUp.units,
        title: unit,
      );
      logsLookUp = CorrelationLookUp.units;
    } else {
      related = correlateUnit(unit, cache);
      final cached = cache.journalByUnit[unit];
      if (cached != null) {
        logsInCache = true;
        lines = cached.take(20).toList();
      } else {
        logsLookUp = CorrelationLookUp.journal;
      }
      actions = _unitActions(unit, readOnly: host.readOnly);
    }
  } else if (focus?.kind == IncidentObjectKind.container) {
    ContainerRow? row;
    for (final c in cache.containers) {
      if (c.title == focus!.name) {
        row = c;
        break;
      }
    }
    if (row != null) {
      related = correlateRestartingContainer(row);
      final cached = cache.containerLogs[row.title];
      if (cached != null) {
        logsInCache = true;
        lines = _containerLogLines(cached, row.title);
      } else {
        logsLookUp = CorrelationLookUp.containerLogs;
      }
    }
    actions = const [
      IncidentAction(
        id: IncidentActionId.containerLogs,
        label: 'Logs',
        risk: RiskLevel.read,
      ),
    ];
  }

  return IncidentSheetView(
    broken: broken,
    lines: lines,
    logsInCache: logsInCache,
    related: related,
    actions: host.readOnly
        ? actions.where((a) => a.risk == RiskLevel.read).toList()
        : actions,
    blocking: false,
    logsLookUp: logsLookUp,
    focus: focus,
  );
}

List<IncidentAction> _unitActions(String unit, {required bool readOnly}) {
  if (readOnly) {
    return const [
      IncidentAction(
        id: IncidentActionId.logs,
        label: 'Logs',
        risk: RiskLevel.read,
      ),
    ];
  }
  final restartRisk = isDestructiveUnitAction(UnitVerb.restart, unit)
      ? RiskLevel.destructive
      : RiskLevel.mutate;
  return [
    IncidentAction(
      id: IncidentActionId.restart,
      label: 'Restart',
      risk: restartRisk,
    ),
    const IncidentAction(
      id: IncidentActionId.logs,
      label: 'Logs',
      risk: RiskLevel.read,
    ),
  ];
}

List<JournalEntry> _containerLogLines(List<String> logs, String unit) {
  return [
    for (var i = 0; i < logs.length && i < 20; i++)
      JournalEntry(
        cursor: '$i',
        realtimeUsec: '',
        priority: 6,
        message: logs[i],
        unit: unit,
      ),
  ];
}

String? incidentChipLabel(Host host, {DateTime? now}) {
  if (host.failedUnitCount != null && host.failedUnitCount! > 0) {
    return host.attentionPill(now: now);
  }
  if (host.diskRootPercent != null && host.diskRootPercent! >= 90) {
    return host.attentionPill(now: now);
  }
  return null;
}
