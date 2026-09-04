import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/lockout.dart';
import 'package:kelola/domain/units/service_unit.dart';

class CatalogEntry {
  const CatalogEntry({
    required this.kind,
    required this.label,
    required this.param,
    required this.baseRisk,
  });

  final String kind;
  final String label;
  final CatalogParam param;
  final RiskLevel baseRisk;
}

enum CatalogParam { unit, path, none }

const assistCatalog = <CatalogEntry>[
  CatalogEntry(
    kind: 'unit_restart',
    label: 'Restart unit',
    param: CatalogParam.unit,
    baseRisk: RiskLevel.mutate,
  ),
  CatalogEntry(
    kind: 'unit_start',
    label: 'Start unit',
    param: CatalogParam.unit,
    baseRisk: RiskLevel.mutate,
  ),
  CatalogEntry(
    kind: 'unit_stop',
    label: 'Stop unit',
    param: CatalogParam.unit,
    baseRisk: RiskLevel.mutate,
  ),
  CatalogEntry(
    kind: 'unit_enable',
    label: 'Enable unit',
    param: CatalogParam.unit,
    baseRisk: RiskLevel.mutate,
  ),
  CatalogEntry(
    kind: 'unit_disable',
    label: 'Disable unit',
    param: CatalogParam.unit,
    baseRisk: RiskLevel.mutate,
  ),
  CatalogEntry(
    kind: 'df_pt',
    label: 'df -PT',
    param: CatalogParam.path,
    baseRisk: RiskLevel.read,
  ),
];

RiskLevel catalogRisk(CatalogEntry entry, {String? unit}) {
  if (entry.param == CatalogParam.unit && unit != null) {
    final verb = switch (entry.kind) {
      'unit_restart' => UnitVerb.restart,
      'unit_start' => UnitVerb.start,
      'unit_stop' => UnitVerb.stop,
      'unit_enable' => UnitVerb.enable,
      'unit_disable' => UnitVerb.disable,
      _ => UnitVerb.restart,
    };
    if (isDestructiveUnitAction(verb, unit)) {
      return RiskLevel.destructive;
    }
  }
  return entry.baseRisk;
}

CatalogEntry? catalogByKind(String kind) {
  for (final e in assistCatalog) {
    if (e.kind == kind) {
      return e;
    }
  }
  return null;
}

String catalogPromptBlock() {
  final buf = StringBuffer(
    'You may only propose actions from this catalog as JSON '
    '{"probeKind":"...","unit":"..."} or {"probeKind":"df_pt","path":"..."}. '
    'If none fits, reply exactly: tidak ada aksi tersedia\n',
  );
  for (final e in assistCatalog) {
    buf.writeln('- ${e.kind}: ${e.label} (${e.param.name})');
  }
  return buf.toString();
}
