import 'package:kelola/domain/services/service_catalog.dart';
import 'package:kelola/domain/services/service_detection.dart';

/// Parses the batched `ServiceDetectProbe` output (`---UNITS---`, `---BIN---`,
/// `---VERSION---`, `---PORTS---`). Junk or missing sections yield empty
/// results; this never throws.
ServiceDetection parseServiceDetection(String stdout, {required DateTime now}) {
  final units = _parseUnits(_section(stdout, 'UNITS') ?? '');
  final bins = _parseBinaries(_section(stdout, 'BIN') ?? '');
  final versions = _parseVersionLines(_section(stdout, 'VERSION') ?? '');
  final ports = _parsePorts(_section(stdout, 'PORTS') ?? '');

  // One unit maps to one id. mysql and mariadb share unit names on Debian,
  // so a "MariaDB" version line decides, and never both.
  final isMaria = _isMariaDb(versions);

  final unitsById = <ServiceId, List<_Unit>>{};
  for (final u in units) {
    final id = _idForUnit(u.name, isMaria: isMaria);
    if (id != null) {
      unitsById.putIfAbsent(id, () => []).add(u);
    }
  }

  final binsById = <ServiceId, Map<String, String>>{};
  for (final d in kServiceCatalog) {
    for (final name in d.binaries) {
      final path = bins[name];
      if (path == null) {
        continue;
      }
      var id = d.id;
      // The mysql client/daemon names are symlinks on MariaDB hosts.
      if (id == ServiceId.mysql && isMaria) {
        id = ServiceId.mariadb;
      }
      binsById.putIfAbsent(id, () => {})[name] = path;
    }
  }

  final services = <DetectedService>[];
  for (final d in kServiceCatalog) {
    final u = _pick(unitsById[d.id]);
    final b = binsById[d.id] ?? const <String, String>{};
    if (u == null && b.isEmpty) {
      continue;
    }
    services.add(
      DetectedService(
        id: d.id,
        state: u?.state ?? ServiceState.installed,
        unit: u?.name,
        version: _versionFor(d.id, versions, isMaria: isMaria),
        binaries: b,
      ),
    );
  }

  return ServiceDetection(
    services: services,
    listeningPorts: ports,
    readAt: now,
  );
}

class _Unit {
  const _Unit(this.name, this.state);
  final String name;
  final ServiceState state;
}

/// Prefers running, then failed, then stopped; first listed wins a tie.
_Unit? _pick(List<_Unit>? units) {
  if (units == null || units.isEmpty) {
    return null;
  }
  for (final s in [
    ServiceState.running,
    ServiceState.failed,
    ServiceState.stopped,
  ]) {
    for (final u in units) {
      if (u.state == s) {
        return u;
      }
    }
  }
  return units.first;
}

ServiceId? _idForUnit(String unit, {required bool isMaria}) {
  final candidates = [
    for (final d in kServiceCatalog)
      if (_matchesUnit(d, unit)) d.id,
  ];
  if (candidates.isEmpty) {
    return null;
  }
  if (candidates.contains(ServiceId.mariadb) &&
      candidates.contains(ServiceId.mysql)) {
    return isMaria ? ServiceId.mariadb : ServiceId.mysql;
  }
  return candidates.first;
}

bool _matchesUnit(ServiceDescriptor d, String unit) =>
    d.matchesSystemdUnit(unit) || d.openrcServices.contains(unit);

final _openrcLine = RegExp(r'^\s*([A-Za-z0-9_.@+-]+)\s+\[\s*([A-Za-z]+)\s*\]');

List<_Unit> _parseUnits(String text) {
  final out = <_Unit>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      continue;
    }
    final rc = _openrcLine.firstMatch(raw);
    if (rc != null) {
      out.add(_Unit(rc.group(1)!, _openrcState(rc.group(2)!)));
      continue;
    }
    final cols = line.split(RegExp(r'\s+'));
    if (cols.length < 2 || !cols.first.endsWith('.service')) {
      continue;
    }
    // Column 2 is systemd's ActiveState.
    out.add(_Unit(cols[0], _systemdState(cols[1])));
  }
  return out;
}

ServiceState _systemdState(String active) {
  switch (active) {
    case 'failed':
      return ServiceState.failed;
    case 'active':
      return ServiceState.running;
    default:
      return ServiceState.stopped;
  }
}

ServiceState _openrcState(String s) {
  switch (s.toLowerCase()) {
    case 'started':
      return ServiceState.running;
    case 'crashed':
      return ServiceState.failed;
    default:
      return ServiceState.stopped;
  }
}

Map<String, String> _parseBinaries(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final t = line.trim();
    final i = t.indexOf(RegExp(r'\s'));
    if (i <= 0) {
      continue;
    }
    final name = t.substring(0, i);
    final path = t.substring(i).trim();
    if (path.startsWith('/')) {
      out.putIfAbsent(name, () => path);
    }
  }
  return out;
}

/// `<service id> <first line of the version command>`.
Map<String, String> _parseVersionLines(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final t = line.trim();
    final i = t.indexOf(RegExp(r'\s'));
    if (i <= 0) {
      continue;
    }
    out.putIfAbsent(t.substring(0, i), () => t.substring(i).trim());
  }
  return out;
}

bool _isMariaDb(Map<String, String> versions) {
  for (final k in const ['mariadb', 'mysql']) {
    if ((versions[k] ?? '').toLowerCase().contains('mariadb')) {
      return true;
    }
  }
  return false;
}

String? _versionFor(
  ServiceId id,
  Map<String, String> versions, {
  required bool isMaria,
}) {
  switch (id) {
    case ServiceId.nginx:
      return _extract(versions['nginx'], RegExp(r'nginx/(\d+(?:\.\d+)*)'));
    case ServiceId.apache:
      return _extract(versions['apache'], RegExp(r'Apache/(\d+(?:\.\d+)*)'));
    case ServiceId.mariadb:
      return _dbVersion(
        isMaria
            ? versions['mariadb'] ?? versions['mysql']
            : versions['mariadb'],
      );
    case ServiceId.mysql:
      return _dbVersion(versions['mysql']);
    case ServiceId.postgres:
      return _dbVersion(versions['postgres']);
  }
}

String? _dbVersion(String? line) =>
    _extract(line, RegExp(r'Distrib (\d+(?:\.\d+)*)')) ??
    _extract(line, RegExp(r'(?<![\d.])(\d+\.\d+(?:\.\d+)*)'));

String? _extract(String? line, RegExp re) {
  if (line == null) {
    return null;
  }
  final m = re.firstMatch(line);
  if (m == null) {
    return null;
  }
  return m.group(1);
}

List<int> _parsePorts(String text) {
  final out = <int>{};
  for (final line in text.split('\n')) {
    final t = line.trim();
    final i = t.lastIndexOf(':');
    if (i < 0) {
      continue;
    }
    final p = int.tryParse(t.substring(i + 1));
    if (p != null && p >= 1 && p <= 65535) {
      out.add(p);
    }
  }
  return out.toList()..sort();
}

String? _section(String stdout, String name) {
  final startTag = '---$name---';
  final start = stdout.indexOf(startTag);
  if (start < 0) {
    return null;
  }
  var from = start + startTag.length;
  if (from < stdout.length && stdout[from] == '\n') {
    from++;
  }
  final rest = stdout.substring(from);
  final next = RegExp(r'\n?---[A-Z0-9_]+---').firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}
