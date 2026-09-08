import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';

/// Projects live host rows into inventory buckets without reshuffling on
/// every attention write. Re-bucket only when [allowReorder] is true or the
/// membership set changes (add/remove). New hosts land in not-checked until
/// the next explicit reorder (pull-to-refresh).
class StableHostInventory {
  Set<String>? _memberIds;
  List<String> _needsIds = const [];
  List<String> _healthyIds = const [];
  List<String> _uncheckedIds = const [];

  HostInventoryView project(
    List<Host> live, {
    required bool allowReorder,
    DateTime? now,
  }) {
    final byId = {for (final h in live) h.id: h};
    final members = byId.keys.toSet();
    final membershipChanged =
        _memberIds == null || !_sameMembers(_memberIds!, members);

    if (allowReorder || membershipChanged) {
      if (!allowReorder && membershipChanged && _memberIds != null) {
        _applyMembershipDelta(byId, members);
        _memberIds = members;
        return _viewFromFrozen(byId);
      }
      final view = HostInventoryView.build(live, now: now);
      _capture(view);
      _memberIds = members;
      return view;
    }

    return _viewFromFrozen(byId);
  }

  void _applyMembershipDelta(Map<String, Host> byId, Set<String> members) {
    bool keep(String id) => members.contains(id);
    _needsIds = _needsIds.where(keep).toList();
    _healthyIds = _healthyIds.where(keep).toList();
    _uncheckedIds = _uncheckedIds.where(keep).toList();
    final known = {..._needsIds, ..._healthyIds, ..._uncheckedIds};
    for (final id in members) {
      if (!known.contains(id)) {
        _uncheckedIds = [..._uncheckedIds, id];
      }
    }
    // Drop ids that somehow lack a live row.
    _needsIds = _needsIds.where(byId.containsKey).toList();
    _healthyIds = _healthyIds.where(byId.containsKey).toList();
    _uncheckedIds = _uncheckedIds.where(byId.containsKey).toList();
  }

  void _capture(HostInventoryView view) {
    _needsIds = view.needsAttention.map((h) => h.id).toList();
    _healthyIds = view.healthy.map((h) => h.id).toList();
    _uncheckedIds = view.notChecked.map((h) => h.id).toList();
  }

  HostInventoryView _viewFromFrozen(Map<String, Host> byId) {
    Host? take(String id) => byId[id];
    return HostInventoryView(
      needsAttention: [
        for (final id in _needsIds)
          if (take(id) != null) take(id)!,
      ],
      healthy: [
        for (final id in _healthyIds)
          if (take(id) != null) take(id)!,
      ],
      notChecked: [
        for (final id in _uncheckedIds)
          if (take(id) != null) take(id)!,
      ],
    );
  }

  static bool _sameMembers(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.containsAll(b);
  }
}
