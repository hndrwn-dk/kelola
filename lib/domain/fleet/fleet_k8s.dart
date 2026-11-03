import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/workload.dart';

/// M32: what the fleet refresh learned about a host's cluster. Built from
/// the same `ClusterHealthProbe` + `WorkloadListProbe` Kubernetes home runs.
class FleetK8sSummary {
  const FleetK8sSummary({
    required this.read,
    this.apiReachable = false,
    this.nodesReady = 0,
    this.nodesTotal = 0,
    this.failedWorkloads = 0,
    this.warningWorkloads = 0,
  });

  /// The cluster's state is known: kubectl answered with JSON, or the API
  /// itself refused the connection ([apiDown]). RBAC denial or a k3s host
  /// without passwordless sudo is `false` and never raises a fleet issue.
  final bool read;
  final bool apiReachable;
  final int nodesReady;
  final int nodesTotal;
  final int failedWorkloads;
  final int warningWorkloads;

  static const unreadable = FleetK8sSummary(read: false);

  /// The API did not answer at all (connection refused / timed out). Known
  /// state, not a permission problem, so it raises `k8sDown`.
  static const apiDown = FleetK8sSummary(read: true);

  factory FleetK8sSummary.from(ClusterHealth cluster, WorkloadInventory inv) {
    if (cluster.missingKubectl || inv.missingKubectl) {
      return unreadable;
    }
    return FleetK8sSummary(
      read: true,
      apiReachable: cluster.apiReachable,
      nodesReady: cluster.nodesReady,
      nodesTotal: cluster.nodesTotal,
      failedWorkloads:
          inv.rows.where((w) => w.health == HealthStatus.failed).length,
      warningWorkloads:
          inv.rows.where((w) => w.health == HealthStatus.warning).length,
    );
  }

  /// API unreachable or a node NotReady.
  bool get down => read && (!apiReachable || nodesReady < nodesTotal);

  bool get workloadsFailing => read && failedWorkloads > 0;

  /// Tile / sheet line: `3/3 nodes · 2 failed`, `API down`, `not readable`.
  String get label {
    if (!read) {
      return 'not readable';
    }
    if (!apiReachable) {
      return 'API down';
    }
    return [
      '$nodesReady/$nodesTotal nodes',
      if (failedWorkloads > 0) '$failedWorkloads failed',
      if (warningWorkloads > 0) '$warningWorkloads warn',
    ].join(' · ');
  }

  String encode() => jsonEncode({
        'read': read,
        'api': apiReachable,
        'nodesReady': nodesReady,
        'nodesTotal': nodesTotal,
        'failed': failedWorkloads,
        'warn': warningWorkloads,
      });

  /// Null for empty (host has no kubectl) or junk.
  static FleetK8sSummary? decode(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }
    try {
      final m = jsonDecode(raw);
      if (m is! Map) {
        return null;
      }
      int n(Object? v) => v is int ? v : 0;
      return FleetK8sSummary(
        read: m['read'] == true,
        apiReachable: m['api'] == true,
        nodesReady: n(m['nodesReady']),
        nodesTotal: n(m['nodesTotal']),
        failedWorkloads: n(m['failed']),
        warningWorkloads: n(m['warn']),
      );
    } on FormatException {
      return null;
    }
  }
}
