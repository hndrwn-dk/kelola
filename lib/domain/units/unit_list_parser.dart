import 'dart:convert';

import 'package:kelola/domain/units/service_unit.dart';

class UnitListParser {
  const UnitListParser();

  UnitListResult parse({
    required String stdout,
    required bool initSupported,
  }) {
    if (!initSupported) {
      return const UnitListResult(units: [], initSupported: false);
    }
    final sections = _sections(stdout);
    final files = _parseUnitFiles(sections['FILES_PLAIN'] ?? '');
    var units = _parseJson(sections['UNITS_JSON'] ?? '');
    if (units.isEmpty) {
      units = _parsePlain(sections['UNITS_PLAIN'] ?? '');
    }
    if (units.isEmpty) {
      units = _parseOpenRc(sections['OPENRC'] ?? '');
    }
    final merged = units.map((u) {
      final state = files[u.name];
      if (state == null || state == u.unitFileState) {
        return u;
      }
      return ServiceUnit(
        name: u.name,
        description: u.description,
        load: u.load,
        active: u.active,
        sub: u.sub,
        unitFileState: state,
      );
    }).toList();
    merged.sort((a, b) {
      if (a.isFailed != b.isFailed) {
        return a.isFailed ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });
    return UnitListResult(units: merged, initSupported: true);
  }

  List<ServiceUnit> _parseJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed[0] != '[') {
      return const [];
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) {
        return const [];
      }
      final out = <ServiceUnit>[];
      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }
        final map = item.cast<String, dynamic>();
        final name = (map['unit'] ?? map['Unit'] ?? '').toString();
        if (name.isEmpty) {
          continue;
        }
        out.add(
          ServiceUnit(
            name: name,
            description: (map['description'] ?? map['Description'] ?? '')
                .toString(),
            load: (map['load'] ?? map['Load'] ?? '').toString(),
            active: (map['active'] ?? map['Active'] ?? '').toString(),
            sub: (map['sub'] ?? map['Sub'] ?? '').toString(),
          ),
        );
      }
      return out;
    } on FormatException {
      return const [];
    }
  }

  List<ServiceUnit> _parsePlain(String raw) {
    final out = <ServiceUnit>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('UNIT')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 4) {
        continue;
      }
      final name = parts[0];
      if (!name.contains('.')) {
        continue;
      }
      out.add(
        ServiceUnit(
          name: name,
          load: parts[1],
          active: parts[2],
          sub: parts[3],
          description: parts.length > 4 ? parts.sublist(4).join(' ') : '',
        ),
      );
    }
    return out;
  }

  List<ServiceUnit> _parseOpenRc(String raw) {
    final out = <ServiceUnit>[];
    final statusRe = RegExp(r'\[\s*([a-z]+)\s*\]', caseSensitive: false);
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('Runlevel') ||
          trimmed.startsWith('Dynamic')) {
        continue;
      }
      final status = statusRe.firstMatch(trimmed);
      if (status == null) {
        continue;
      }
      final name = trimmed.substring(0, status.start).trim();
      if (name.isEmpty) {
        continue;
      }
      final st = status.group(1)!.toLowerCase();
      final active = switch (st) {
        'started' => 'active',
        'stopped' => 'inactive',
        'crashed' => 'failed',
        _ => st,
      };
      out.add(
        ServiceUnit(
          name: name,
          description: '',
          load: 'loaded',
          active: active,
          sub: st,
        ),
      );
    }
    return out;
  }

  Map<String, String> _parseUnitFiles(String raw) {
    final out = <String, String>{};
    for (final line in raw.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        continue;
      }
      out[parts[0]] = parts[1];
    }
    return out;
  }

  Map<String, String> _sections(String stdout) {
    final sections = <String, String>{};
    final re = RegExp(r'^---([A-Z_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      final name = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      sections[name] = stdout.substring(start, end).replaceAll('\r', '').trim();
    }
    return sections;
  }
}
