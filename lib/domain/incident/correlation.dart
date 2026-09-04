import 'package:kelola/domain/containers/container_list_view.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/dashboard_snapshot.dart';
import 'package:kelola/domain/journal/journal_entry.dart';
import 'package:kelola/domain/network/network_snapshot.dart';
import 'package:kelola/domain/processes/process_row.dart';
import 'package:kelola/domain/probes/container_logs_probe.dart';
import 'package:kelola/domain/probes/journal_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/units/service_unit.dart';
import 'package:kelola/domain/llm/explain_context.dart';

const cacheMissLookUp = 'not in cache — look up';

enum CorrelationLookUp {
  processes,
  ports,
  units,
  containers,
  journal,
  containerLogs,
}

class RelatedEntity {
  const RelatedEntity({
    required this.title,
    required this.meta,
    required this.cached,
    this.lookUp,
  });

  final String title;
  final String meta;
  final bool cached;
  final CorrelationLookUp? lookUp;

  static const empty = RelatedEntity(title: '', meta: '', cached: true);

  static RelatedEntity miss({
    required CorrelationLookUp lookUp,
    String title = '',
  }) {
    return RelatedEntity(
      title: title,
      meta: cacheMissLookUp,
      cached: false,
      lookUp: lookUp,
    );
  }
}

class CorrelationSnapshot {
  const CorrelationSnapshot({
    this.failedUnitNames = const [],
    this.units = const [],
    this.containers = const [],
    this.processes = const [],
    this.ports = const [],
    this.journalByUnit = const {},
    this.containerLogs = const {},
  });

  final List<String> failedUnitNames;
  final List<ServiceUnit> units;
  final List<ContainerRow> containers;
  final List<ProcessRow> processes;
  final List<ListenPort> ports;
  final Map<String, List<JournalEntry>> journalByUnit;
  final Map<String, List<String>> containerLogs;

  CorrelationSnapshot copyWith({
    List<String>? failedUnitNames,
    List<ServiceUnit>? units,
    List<ContainerRow>? containers,
    List<ProcessRow>? processes,
    List<ListenPort>? ports,
    Map<String, List<JournalEntry>>? journalByUnit,
    Map<String, List<String>>? containerLogs,
  }) {
    return CorrelationSnapshot(
      failedUnitNames: failedUnitNames ?? this.failedUnitNames,
      units: units ?? this.units,
      containers: containers ?? this.containers,
      processes: processes ?? this.processes,
      ports: ports ?? this.ports,
      journalByUnit: journalByUnit ?? this.journalByUnit,
      containerLogs: containerLogs ?? this.containerLogs,
    );
  }
}

RelatedEntity correlatePort(ListenPort port, CorrelationSnapshot cache) {
  if (cache.processes.isEmpty) {
    return RelatedEntity.miss(lookUp: CorrelationLookUp.processes);
  }
  ProcessRow? proc;
  if (port.pid != null) {
    for (final p in cache.processes) {
      if (p.pid == port.pid) {
        proc = p;
        break;
      }
    }
  }
  proc ??= _processNamed(cache.processes, port.process);
  if (proc == null) {
    return RelatedEntity.miss(lookUp: CorrelationLookUp.units);
  }
  final unit = _unitForCommand(cache.units, proc.command);
  if (unit != null) {
    return RelatedEntity(
      title: unit.name,
      meta: 'pid ${proc.pid} · ${port.local}',
      cached: true,
    );
  }
  final container = _containerForProcess(cache.containers, proc, port);
  if (container != null) {
    return RelatedEntity(
      title: container.title,
      meta: 'pid ${proc.pid} · ${port.local}',
      cached: true,
    );
  }
  return RelatedEntity(
    title: proc.command,
    meta: 'pid ${proc.pid}',
    cached: true,
  );
}

RelatedEntity correlateUnit(String unit, CorrelationSnapshot cache) {
  if (cache.processes.isEmpty) {
    return RelatedEntity.miss(
      lookUp: CorrelationLookUp.processes,
      title: unit,
    );
  }
  final proc = _processNamed(cache.processes, _unitBasename(unit));
  if (proc == null) {
    return RelatedEntity(
      title: unit,
      meta: 'no matching pid',
      cached: true,
    );
  }
  ListenPort? listen;
  for (final p in cache.ports) {
    if (p.pid == proc.pid) {
      listen = p;
      break;
    }
  }
  final bits = <String>['pid ${proc.pid}'];
  if (listen != null) {
    bits.add(listen.local);
  }
  return RelatedEntity(title: unit, meta: bits.join(' · '), cached: true);
}

RelatedEntity correlateRestartingContainer(ContainerRow row) {
  final stack = row.composeProject.trim();
  if (stack.isEmpty) {
    return RelatedEntity.miss(
      lookUp: CorrelationLookUp.containers,
      title: row.title,
    );
  }
  return RelatedEntity(title: stack, meta: 'compose stack', cached: true);
}

class CorrelationStore {
  final _byHost = <String, CorrelationSnapshot>{};

  CorrelationSnapshot get(String hostId) {
    return _byHost[hostId] ?? const CorrelationSnapshot();
  }

  void ingest(String hostId, Probe<dynamic> probe, Object? parsed) {
    var snap = get(hostId);
    if (parsed is DashboardSnapshot) {
      snap = snap.copyWith(failedUnitNames: parsed.failedUnitNames);
    } else if (parsed is UnitListResult) {
      snap = snap.copyWith(
        units: parsed.units,
        failedUnitNames: parsed.failed.map((u) => u.name).toList(),
      );
    } else if (parsed is ContainerInventory) {
      snap = snap.copyWith(containers: parsed.rows);
    } else if (parsed is List<ProcessRow>) {
      snap = snap.copyWith(processes: parsed);
    } else if (parsed is NetworkSnapshot) {
      snap = snap.copyWith(ports: parsed.ports);
    } else if (parsed is JournalPage && probe is JournalProbe) {
      final key = (probe.unit ?? '').trim();
      if (key.isNotEmpty) {
        final next = Map<String, List<JournalEntry>>.from(snap.journalByUnit);
        next[key] = parsed.entries;
        snap = snap.copyWith(journalByUnit: next);
      }
    } else if (parsed is UnitDetail) {
      final key = parsed.name.trim();
      if (key.isNotEmpty) {
        final lines = journalLinesFromUnitDetail(parsed);
        final entries = [
          for (var i = 0; i < lines.length; i++)
            JournalEntry(
              cursor: 'unit-detail-$i',
              realtimeUsec: '0',
              priority: 3,
              message: lines[i],
              unit: key,
            ),
        ];
        final next = Map<String, List<JournalEntry>>.from(snap.journalByUnit);
        next[key] = entries;
        snap = snap.copyWith(journalByUnit: next);
      }
    } else if (parsed is List<String> && probe is ContainerLogsProbe) {
      final next = Map<String, List<String>>.from(snap.containerLogs);
      next[probe.row.title] = parsed;
      snap = snap.copyWith(containerLogs: next);
    }
    _byHost[hostId] = snap;
  }

  void mergeFailedNames(String hostId, List<String> names) {
    _byHost[hostId] = get(hostId).copyWith(failedUnitNames: names);
  }
}

String _unitBasename(String unit) {
  final n = unit.trim().toLowerCase();
  if (n.endsWith('.service')) {
    return n.substring(0, n.length - 8);
  }
  return n;
}

ProcessRow? _processNamed(List<ProcessRow> processes, String name) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) {
    return null;
  }
  for (final p in processes) {
    final cmd = p.command.toLowerCase();
    if (cmd == n || cmd.endsWith('/$n') || cmd.contains(n)) {
      return p;
    }
  }
  return null;
}

ServiceUnit? _unitForCommand(List<ServiceUnit> units, String command) {
  for (final u in units) {
    if (_processNamed([
          ProcessRow(
            pid: 0,
            ppid: 0,
            user: '',
            cpu: 0,
            mem: 0,
            rssKb: 0,
            stat: '',
            command: command,
          ),
        ], _unitBasename(u.name)) !=
        null) {
      return u;
    }
  }
  return null;
}

ContainerRow? _containerForProcess(
  List<ContainerRow> rows,
  ProcessRow proc,
  ListenPort port,
) {
  final n = proc.command.toLowerCase();
  for (final c in rows) {
    if (c.names.toLowerCase() == n || c.title.toLowerCase() == n) {
      return c;
    }
    final ports = '${c.publishedPorts} ${c.ports}';
    if (port.local.contains(':') && ports.contains(port.local.split(':').last)) {
      return c;
    }
  }
  return null;
}

bool snapshotHasRestarting(CorrelationSnapshot cache) {
  return cache.containers.any(isRestartingContainer);
}
