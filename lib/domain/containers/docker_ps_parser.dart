import 'dart:convert';

import 'package:kelola/domain/containers/container_ps_common.dart';
import 'package:kelola/domain/containers/container_row.dart';

List<ContainerRow> parseDockerNdjson(String body) {
  final out = <ContainerRow>[];
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed[0] != '{') {
      continue;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        continue;
      }
      final row = rowFromPsMap(decoded.cast<String, dynamic>(), 'docker');
      if (row.id.isEmpty) {
        continue;
      }
      out.add(row);
    } on FormatException {
      continue;
    }
  }
  return out;
}
