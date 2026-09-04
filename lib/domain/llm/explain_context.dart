import 'package:kelola/domain/units/service_unit.dart';

/// Compact systemctl show fields for Assist — Result / exit status matter most.
String formatUnitShowForAssist(UnitDetail detail) {
  final keys = <String>[
    'Id',
    'Description',
    'LoadState',
    'ActiveState',
    'SubState',
    'Result',
    'ExecMainCode',
    'ExecMainStatus',
    'ExecMainPID',
    'MainPID',
    'FragmentPath',
    'UnitFileState',
  ];
  final buf = StringBuffer();
  for (final k in keys) {
    final v = detail.properties[k];
    if (v == null || v.trim().isEmpty) {
      continue;
    }
    buf.writeln('$k=$v');
  }
  return buf.toString().trim();
}

List<String> journalLinesFromUnitDetail(UnitDetail detail, {int limit = 50}) {
  return detail.logs
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty)
      .take(limit)
      .toList(growable: false);
}
