import 'dart:convert';
import 'dart:io';

/// JSON file of host ids chosen for the free fleet probe.
/// Not SharedPreferences — the Android widget reads that file itself.
class FleetProbeSelectionStore {
  FleetProbeSelectionStore(File file)
      : _file = file,
        _memory = null,
        _memoryChosen = false;

  FleetProbeSelectionStore.memory()
      : _file = null,
        _memory = null,
        _memoryChosen = false;

  final File? _file;
  Set<String>? _memory;
  bool _memoryChosen;

  /// Null means the user has never chosen. An empty set is an explicit choice
  /// of zero hosts. Deleted host ids are dropped and do not keep a slot.
  Future<Set<String>?> read(Set<String> liveHostIds) async {
    final stored = await _load();
    if (stored == null) {
      return null;
    }
    final kept = stored.intersection(liveHostIds);
    if (kept.length != stored.length) {
      await write(kept);
    }
    return kept;
  }

  Future<void> write(Set<String> ids) async {
    final file = _file;
    if (file == null) {
      _memoryChosen = true;
      _memory = Set<String>.of(ids);
      return;
    }
    await file.parent.create(recursive: true);
    final ordered = ids.toList()..sort();
    await file.writeAsString(jsonEncode(ordered));
  }

  Future<Set<String>?> _load() async {
    if (_file == null) {
      if (!_memoryChosen) {
        return null;
      }
      return Set<String>.of(_memory ?? const {});
    }
    final file = _file;
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return {};
    }
    return {
      for (final item in decoded)
        if (item is String) item,
    };
  }
}
