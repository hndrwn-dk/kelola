import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';

/// Keeps order inside a bucket stable, but never leaves a host in a bucket
/// that disagrees with its live attention. The row subtitle and the group
/// header both come from the current host.
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

    final liveView = HostInventoryView.build(live, now: now);
    if (allowReorder || _memberIds == null) {
      _capture(liveView);
      _memberIds = members;
      return liveView;
    }
    if (membershipChanged) {
      _memberIds = members;
    }
    return _placeByLiveBucket(liveView);
  }

  /// Bucket comes from the same live host the row subtitle uses. Order
  /// inside a bucket stays put so a refresh does not reshuffle the list.
  HostInventoryView _placeByLiveBucket(HostInventoryView live) {
    List<Host> order(List<Host> group, List<String> previous) {
      final remaining = {for (final host in group) host.id: host};
      final kept = <Host>[
        for (final id in previous)
          if (remaining.containsKey(id)) remaining.remove(id)!,
      ];
      final added = remaining.values.toList()
        ..sort(
          (a, b) => a.alias.toLowerCase().compareTo(b.alias.toLowerCase()),
        );
      return [...kept, ...added];
    }

    final needs = order(live.needsAttention, _needsIds);
    final healthy = order(live.healthy, _healthyIds);
    final unchecked = order(live.notChecked, _uncheckedIds);
    _needsIds = needs.map((host) => host.id).toList();
    _healthyIds = healthy.map((host) => host.id).toList();
    _uncheckedIds = unchecked.map((host) => host.id).toList();
    return HostInventoryView(
      needsAttention: needs,
      healthy: healthy,
      notChecked: unchecked,
    );
  }

  void _capture(HostInventoryView view) {
    _needsIds = view.needsAttention.map((h) => h.id).toList();
    _healthyIds = view.healthy.map((h) => h.id).toList();
    _uncheckedIds = view.notChecked.map((h) => h.id).toList();
  }

  static bool _sameMembers(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.containsAll(b);
  }
}
