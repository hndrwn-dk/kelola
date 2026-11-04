import 'dart:convert';
import 'dart:io';

import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';

/// M48: host id → [ClusterKindRecord]. A JSON file (no schema change). A
/// cache only: not a host fact and not vault-synced, because the cluster
/// follows the kubeconfig context.
class ClusterKindStore {
  ClusterKindStore(File file) : _file = file;

  ClusterKindStore.memory() : _file = null;

  final File? _file;
  final Map<String, ClusterKindRecord> _memory = {};

  Future<ClusterKindRecord?> read(String hostId) async =>
      (await _load())[hostId];

  /// Fold [health] into the host's record ([mergeClusterKind]).
  Future<void> recordRead(String hostId, ClusterHealth health, DateTime at) async {
    final all = await _load();
    final next = mergeClusterKind(all[hostId], health, at);
    if (next == null) {
      return;
    }
    all[hostId] = next;
    await _save(all);
  }

  Future<void> write(String hostId, ClusterKindRecord record) async {
    final all = await _load()..[hostId] = record;
    await _save(all);
  }

  /// Host removed: forget its entry.
  Future<void> remove(String hostId) async {
    final all = await _load();
    if (all.remove(hostId) != null) {
      await _save(all);
    }
  }

  Future<void> _save(Map<String, ClusterKindRecord> all) async {
    final file = _file;
    if (file == null) {
      _memory
        ..clear()
        ..addAll(all);
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        for (final e in all.entries)
          e.key: {
            'openShift': e.value.isOpenShift,
            'at': e.value.readAt.toUtc().toIso8601String(),
            'ctx': e.value.kubeContext,
            if (e.value.seenContext != null) 'seen': e.value.seenContext,
          },
      }),
    );
  }

  Future<Map<String, ClusterKindRecord>> _load() async {
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
      final out = <String, ClusterKindRecord>{};
      for (final e in decoded.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) {
          continue;
        }
        final kind = v['openShift'];
        final at = DateTime.tryParse(v['at'] is String ? v['at'] as String : '');
        if (kind is bool && at != null) {
          out[e.key as String] = ClusterKindRecord(
            isOpenShift: kind,
            readAt: at,
            kubeContext: v['ctx'] is String ? v['ctx'] as String : '',
            seenContext: v['seen'] is String ? v['seen'] as String : null,
          );
        }
      }
      return out;
    } on FormatException {
      return {};
    }
  }
}
