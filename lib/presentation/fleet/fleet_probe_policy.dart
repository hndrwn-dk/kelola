import 'package:kelola/domain/hosts/host.dart';
import 'package:kelola/domain/hosts/host_inventory_view.dart';

/// Free-fleet cap lives in the app so public and private builds cannot diverge.
const kFreeFleetHostLimit = 3;

class FleetProbePlan {
  const FleetProbePlan({
    required this.probedHostIds,
    required this.addHostLocked,
    required this.showProbeToggles,
    required this.showChoosePrompt,
    required this.selectedHostIds,
    required this.selectionAtCap,
  });

  final Set<String> probedHostIds;
  final bool addHostLocked;
  final bool showProbeToggles;
  final bool showChoosePrompt;
  final Set<String> selectedHostIds;
  final bool selectionAtCap;

  bool isMonitored(String hostId) => probedHostIds.contains(hostId);

  /// True when adding [hostId] to the probe set would exceed the free cap.
  /// Already-selected hosts are never locked — deselect must stay possible.
  bool selectingAnotherIsLocked(String hostId) {
    if (selectedHostIds.contains(hostId)) {
      return false;
    }
    return selectionAtCap;
  }
}

/// Single table for fleet probe filtering, add-host, fourth toggle, and
/// the "not monitored" overlay. Call sites must not copy this decision.
///
/// [selectedHostIds] is null when the user has never chosen. An empty set is
/// an explicit choice of zero hosts — not the same as never choosing, and not
/// a reason to probe everyone or to invent a selection.
FleetProbePlan planFleetProbes({
  required List<String> hostIds,
  required Set<String>? selectedHostIds,
  required bool fleetUnlimited,
}) {
  final live = hostIds.toSet();
  final selected = selectedHostIds?.intersection(live);
  if (fleetUnlimited) {
    return FleetProbePlan(
      probedHostIds: live,
      addHostLocked: false,
      showProbeToggles: false,
      showChoosePrompt: false,
      selectedHostIds: selected ?? const {},
      selectionAtCap: false,
    );
  }
  if (hostIds.length <= kFreeFleetHostLimit) {
    return FleetProbePlan(
      probedHostIds: live,
      addHostLocked: hostIds.length >= kFreeFleetHostLimit,
      showProbeToggles: false,
      showChoosePrompt: false,
      selectedHostIds: selected ?? const {},
      selectionAtCap: false,
    );
  }
  if (selectedHostIds == null) {
    return const FleetProbePlan(
      probedHostIds: {},
      addHostLocked: true,
      showProbeToggles: true,
      showChoosePrompt: true,
      selectedHostIds: {},
      selectionAtCap: false,
    );
  }
  final chosen = selectedHostIds.intersection(live);
  final ordered = [
    for (final id in hostIds)
      if (chosen.contains(id)) id,
  ];
  final capped = ordered.take(kFreeFleetHostLimit).toSet();
  return FleetProbePlan(
    probedHostIds: capped,
    addHostLocked: true,
    showProbeToggles: true,
    showChoosePrompt: false,
    selectedHostIds: chosen,
    selectionAtCap: chosen.length >= kFreeFleetHostLimit,
  );
}

class DisplayedInventory {
  const DisplayedInventory({
    required this.monitored,
    required this.unmonitored,
  });

  final HostInventoryView monitored;
  final List<Host> unmonitored;

  String get summary {
    final base = monitored.summary;
    if (unmonitored.isEmpty) {
      return base;
    }
    return '$base · ${unmonitored.length} not monitored';
  }
}

/// Unmonitored hosts are an overlay, not a stored health. They must not
/// sit in healthy or needs-attention, and this does not write the database.
DisplayedInventory splitUnmonitored(
  HostInventoryView view,
  bool Function(String hostId) isMonitored,
) {
  final skipped = <Host>[];
  List<Host> keep(List<Host> hosts) {
    final kept = <Host>[];
    for (final host in hosts) {
      if (isMonitored(host.id)) {
        kept.add(host);
      } else {
        skipped.add(host);
      }
    }
    return kept;
  }

  return DisplayedInventory(
    monitored: HostInventoryView(
      needsAttention: keep(view.needsAttention),
      healthy: keep(view.healthy),
      notChecked: keep(view.notChecked),
    ),
    unmonitored: skipped,
  );
}
