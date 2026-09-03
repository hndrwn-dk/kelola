import 'dart:convert';

import 'package:kelola/domain/containers/container_ps_common.dart';
import 'package:kelola/domain/containers/container_row.dart';

List<ContainerRow> parsePodmanJson(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    return const [];
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      return const [];
    }
    final out = <ContainerRow>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }
      final row = rowFromPsMap(item.cast<String, dynamic>(), 'podman');
      if (row.id.isEmpty) {
        continue;
      }
      out.add(row);
    }
    return out;
  } on FormatException {
    return const [];
  }
}
