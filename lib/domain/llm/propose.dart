import 'dart:convert';

import 'package:kelola/domain/llm/assist_context.dart';
import 'package:kelola/domain/llm/catalog.dart';
import 'package:kelola/domain/risk/risk_level.dart';

class ProbeProposal {
  const ProbeProposal({
    required this.available,
    this.probeKind,
    this.unit,
    this.path,
    this.risk = RiskLevel.read,
    this.message = '',
    this.label = '',
  });

  final bool available;
  final String? probeKind;
  final String? unit;
  final String? path;
  final RiskLevel risk;
  final String message;
  final String label;

  static const unavailable = ProbeProposal(
    available: false,
    message: 'tidak ada aksi tersedia',
  );
}

ProbeProposal parseProbeProposal(
  String raw, {
  required List<CatalogEntry> catalog,
  required AssistContext context,
}) {
  final text = raw.trim();
  if (text.toLowerCase().contains('tidak ada aksi tersedia')) {
    return ProbeProposal.unavailable;
  }
  Map<String, dynamic>? json;
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start >= 0 && end > start) {
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) {
        json = decoded;
      } else if (decoded is Map) {
        json = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return ProbeProposal.unavailable;
    }
  }
  if (json == null) {
    return ProbeProposal.unavailable;
  }
  final kind = (json['probeKind'] as String?)?.trim() ?? '';
  final entry = catalogByKind(kind);
  if (entry == null || !catalog.any((e) => e.kind == kind)) {
    return ProbeProposal.unavailable;
  }
  switch (entry.param) {
    case CatalogParam.unit:
      final unit = (json['unit'] as String?)?.trim() ?? '';
      if (unit.isEmpty || !context.allowsUnit(unit)) {
        return ProbeProposal.unavailable;
      }
      return ProbeProposal(
        available: true,
        probeKind: kind,
        unit: unit,
        risk: catalogRisk(entry, unit: unit),
        label: entry.label,
      );
    case CatalogParam.path:
      final path = (json['path'] as String?)?.trim() ?? '';
      if (path.isEmpty || !context.allowsPath(path)) {
        return ProbeProposal.unavailable;
      }
      return ProbeProposal(
        available: true,
        probeKind: kind,
        path: path,
        risk: entry.baseRisk,
        label: entry.label,
      );
    case CatalogParam.none:
      return ProbeProposal(
        available: true,
        probeKind: kind,
        risk: entry.baseRisk,
        label: entry.label,
      );
  }
}
