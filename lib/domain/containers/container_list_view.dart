import 'package:kelola/domain/containers/container_row.dart';

enum ContainerListFilter { running, stopped, unhealthy, all }

enum ContainerHealth { healthy, warning, failed, unknown }

class ContainerListCounts {
  const ContainerListCounts({
    required this.running,
    required this.stopped,
    required this.unhealthy,
    required this.all,
  });

  final int running;
  final int stopped;
  final int unhealthy;
  final int all;

  factory ContainerListCounts.from(List<ContainerRow> rows) {
    var running = 0;
    var stopped = 0;
    var unhealthy = 0;
    for (final r in rows) {
      if (isUnhealthyContainer(r)) {
        unhealthy++;
      }
      if (r.running) {
        running++;
      } else if (!isRestartingContainer(r)) {
        stopped++;
      }
    }
    return ContainerListCounts(
      running: running,
      stopped: stopped,
      unhealthy: unhealthy,
      all: rows.length,
    );
  }
}

class ContainerStackGroup {
  const ContainerStackGroup({required this.label, required this.rows});

  final String label;
  final List<ContainerRow> rows;
}

class ContainerListView {
  const ContainerListView({
    required this.rows,
    required this.groups,
  });

  final List<ContainerRow> rows;
  final List<ContainerStackGroup> groups;

  bool get isEmpty => rows.isEmpty;

  static ContainerListView build(
    List<ContainerRow> rows,
    ContainerListFilter filter, {
    String query = '',
  }) {
    var list = switch (filter) {
      ContainerListFilter.running => rows.where((r) => r.running).toList(),
      ContainerListFilter.stopped =>
        rows.where((r) => !r.running && !isRestartingContainer(r)).toList(),
      ContainerListFilter.unhealthy =>
        rows.where(isUnhealthyContainer).toList(),
      ContainerListFilter.all => rows,
    };
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (r) =>
                r.names.toLowerCase().contains(q) ||
                r.image.toLowerCase().contains(q) ||
                r.title.toLowerCase().contains(q),
          )
          .toList();
    }
    return ContainerListView(
      rows: list,
      groups: groupContainersByCompose(list),
    );
  }
}

bool isRestartingContainer(ContainerRow row) =>
    row.state.toLowerCase() == 'restarting';

bool isUnhealthyContainer(ContainerRow row) {
  if (isRestartingContainer(row)) {
    return true;
  }
  return row.status.toLowerCase().contains('unhealthy');
}

ContainerListFilter defaultContainerListFilter(List<ContainerRow> rows) {
  return rows.any(isUnhealthyContainer)
      ? ContainerListFilter.unhealthy
      : ContainerListFilter.all;
}

String containerListChipLabel(
  ContainerListFilter filter,
  ContainerListCounts counts,
) {
  return switch (filter) {
    ContainerListFilter.running => 'Running ${counts.running}',
    ContainerListFilter.stopped => 'Stopped ${counts.stopped}',
    ContainerListFilter.unhealthy => 'Unhealthy ${counts.unhealthy}',
    ContainerListFilter.all => 'All ${counts.all}',
  };
}

String containerListEmptyCopy(ContainerListFilter filter, {String query = ''}) {
  if (query.trim().isNotEmpty) {
    return 'No containers match.';
  }
  return switch (filter) {
    ContainerListFilter.running => 'No running containers.',
    ContainerListFilter.stopped => 'No stopped containers.',
    ContainerListFilter.unhealthy => 'No unhealthy containers.',
    ContainerListFilter.all => 'No containers.',
  };
}

String containerListKicker(
  List<ContainerRow> rows, {
  List<String> engines = const [],
}) {
  final engine = _kickerEngine(rows, engines);
  var running = 0;
  var stopped = 0;
  for (final r in rows) {
    if (r.running) {
      running++;
    } else {
      stopped++;
    }
  }
  return '$engine · $running RUNNING · $stopped STOPPED';
}

String _kickerEngine(List<ContainerRow> rows, List<String> engines) {
  if (rows.any((r) => r.engine == 'docker')) {
    return 'DOCKER';
  }
  if (rows.any((r) => r.engine == 'podman')) {
    return 'PODMAN';
  }
  if (engines.contains('docker')) {
    return 'DOCKER';
  }
  if (engines.contains('podman')) {
    return 'PODMAN';
  }
  if (rows.isNotEmpty && rows.first.engine.isNotEmpty) {
    return rows.first.engine.toUpperCase();
  }
  return 'DOCKER';
}

List<ContainerStackGroup> groupContainersByCompose(List<ContainerRow> rows) {
  final stacks = <String, List<ContainerRow>>{};
  final standalone = <ContainerRow>[];
  for (final r in rows) {
    final project = r.composeProject.trim();
    if (project.isEmpty) {
      standalone.add(r);
    } else {
      stacks.putIfAbsent(project, () => []).add(r);
    }
  }
  final names = stacks.keys.toList()..sort();
  return [
    for (final name in names)
      ContainerStackGroup(label: name, rows: stacks[name]!),
    if (standalone.isNotEmpty)
      ContainerStackGroup(label: 'STANDALONE', rows: standalone),
  ];
}

String containerListMeta(ContainerRow row) {
  final state = row.state.toLowerCase();
  if (state == 'restarting') {
    return row.status.isEmpty ? 'restarting' : 'restarting · ${row.status}';
  }
  if (state == 'exited' || state == 'dead') {
    return row.status.isNotEmpty ? row.status : state;
  }
  final bits = <String>[];
  if (row.image.isNotEmpty) {
    bits.add(row.image);
  }
  final ports =
      row.publishedPorts.isNotEmpty ? row.publishedPorts : row.ports;
  if (ports.isNotEmpty) {
    bits.add(ports);
  }
  return bits.join(' · ');
}

ContainerHealth containerHealth(ContainerRow row) {
  final state = row.state.toLowerCase();
  final status = row.status.toLowerCase();
  if (state == 'restarting' || status.contains('unhealthy')) {
    return ContainerHealth.warning;
  }
  if (row.running) {
    return ContainerHealth.healthy;
  }
  if (state == 'exited' || state == 'dead') {
    final code = row.exitCode;
    if (code != null && code != 0) {
      return ContainerHealth.failed;
    }
    return ContainerHealth.unknown;
  }
  return ContainerHealth.unknown;
}

String? containerUptimePill(ContainerRow row) {
  final blob = '${row.status} ';
  final days = RegExp(r'Up\s+(\d+)\s+days?', caseSensitive: false).firstMatch(blob);
  if (days != null) {
    return '${days.group(1)}d';
  }
  final hours =
      RegExp(r'Up\s+(\d+)\s+hours?', caseSensitive: false).firstMatch(blob);
  if (hours != null) {
    return '${hours.group(1)}h';
  }
  final mins =
      RegExp(r'Up\s+(\d+)\s+minutes?', caseSensitive: false).firstMatch(blob);
  if (mins != null) {
    return '${mins.group(1)}m';
  }
  return null;
}

String? containerListPill(ContainerRow row) {
  if (row.status.toLowerCase().contains('unhealthy')) {
    return 'unhealthy';
  }
  return containerUptimePill(row);
}
