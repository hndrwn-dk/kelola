import 'dart:convert';
import 'dart:io';

import 'package:kelola/domain/services/service_detection.dart';

/// M52: host id → last [ServiceDetection]. A JSON file (no schema change).
/// A cache only: not a host fact and not vault-synced.
class ServiceLensStore {
  ServiceLensStore(File file) : _file = file;

  ServiceLensStore.memory() : _file = null;

  final File? _file;
  final Map<String, ServiceDetection> _memory = {};

  /// Read-modify-write cycles run one at a time so concurrent writers
  /// (dashboard and fleet) cannot drop each other's entries.
  Future<void> _tail = Future<void>.value();

  Future<ServiceDetection?> read(String hostId) async =>
      (await _load())[hostId];

  Future<Map<String, ServiceDetection>> readAll() => _load();

  Future<void> write(String hostId, ServiceDetection detection) =>
      _serial(() async {
        final all = await _load()
          ..[hostId] = detection;
        await _save(all);
      });

  /// Host removed: forget its entry.
  Future<void> remove(String hostId) => _serial(() async {
    final all = await _load();
    if (all.remove(hostId) != null) {
      await _save(all);
    }
  });

  Future<void> _serial(Future<void> Function() action) {
    final run = _tail.then((_) => action());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _save(Map<String, ServiceDetection> all) async {
    final file = _file;
    if (file == null) {
      _memory
        ..clear()
        ..addAll(all);
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({for (final e in all.entries) e.key: e.value.toJson()}),
    );
  }

  Future<Map<String, ServiceDetection>> _load() async {
    final file = _file;
    if (file == null) {
      return Map.of(_memory);
    }
    try {
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return {};
      }
      final out = <String, ServiceDetection>{};
      for (final e in decoded.entries) {
        final d = e.key is String ? ServiceDetection.fromJson(e.value) : null;
        if (d != null) {
          out[e.key as String] = d;
        }
      }
      return out;
    } on FormatException {
      return {};
    }
  }
}
