import 'package:kelola/domain/units/service_unit.dart';

class UnitDetailParser {
  const UnitDetailParser();

  UnitDetail parse(String stdout, String name) {
    final sections = <String, String>{};
    final re = RegExp(r'^---([A-Z_]+)---\s*$', multiLine: true);
    final matches = re.allMatches(stdout).toList();
    for (var i = 0; i < matches.length; i++) {
      final key = matches[i].group(1)!;
      final start = matches[i].end;
      final end = i + 1 < matches.length ? matches[i + 1].start : stdout.length;
      sections[key] = stdout.substring(start, end).replaceAll('\r', '').trim();
    }

    final properties = <String, String>{};
    for (final line in (sections['SHOW'] ?? '').split('\n')) {
      final cleaned = line.trim();
      final idx = cleaned.indexOf('=');
      if (idx <= 0) {
        continue;
      }
      properties[cleaned.substring(0, idx)] = cleaned.substring(idx + 1);
    }

    return UnitDetail(
      name: properties['Id'] ?? name,
      properties: properties,
      logs: sections['LOGS'] ?? '',
      dependencies: sections['DEPS'] ?? '',
    );
  }
}
