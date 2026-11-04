import 'dart:convert';
import 'dart:io';

/// M48 §4: host ids whose "this is an OpenShift node" notice was
/// acknowledged with Continue. A JSON file like the fleet selection, so no
/// schema change; vault sync carries it in the prefs record.
class CoreOsAckStore {
  CoreOsAckStore(File file) : _file = file;

  CoreOsAckStore.memory() : _file = null;

  final File? _file;
  final Set<String> _memory = {};

  Future<bool> isAcknowledged(String hostId) async =>
      (await read()).contains(hostId);

  Future<Set<String>> read() async {
    final file = _file;
    if (file == null) {
      return Set<String>.of(_memory);
    }
    try {
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return {};
      }
      return {
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> acknowledge(String hostId) async {
    await write({...await read(), hostId});
  }

  /// Vault apply: acknowledgements only accumulate across devices.
  Future<void> merge(Iterable<String> hostIds) async {
    await write({...await read(), ...hostIds});
  }

  Future<void> write(Set<String> ids) async {
    final file = _file;
    if (file == null) {
      _memory
        ..clear()
        ..addAll(ids);
      return;
    }
    await file.parent.create(recursive: true);
    final ordered = ids.toList()..sort();
    await file.writeAsString(jsonEncode(ordered));
  }
}
