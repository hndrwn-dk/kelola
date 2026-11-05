import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/workload.dart';

/// M48 §4: the host id of a bastion whose cached cluster node list contains
/// [hostname] (short name, or FQDN either way). Cached data only.
String? clusterBastionFor(
  String hostname,
  Map<String, FleetK8sSummary?> summariesByHostId, {
  String? selfHostId,
}) {
  final h = hostname.trim().toLowerCase();
  if (h.isEmpty) {
    return null;
  }
  final ids = summariesByHostId.keys.toList()..sort();
  for (final id in ids) {
    if (id == selfHostId) {
      continue;
    }
    for (final node in summariesByHostId[id]?.nodes ?? const <String>[]) {
      final n = node.toLowerCase();
      if (n == h || n.startsWith('$h.') || h.startsWith('$n.')) {
        return id;
      }
    }
  }
  return null;
}

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
    this.nodes = const [],
    this.ocp,
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

  /// M48: node names from the last cluster read. Lets an RHCOS host find
  /// "its" bastion from cached data only (no SSH to the bastion).
  final List<String> nodes;

  /// M48 §5: OpenShift health from fleet. Null off OpenShift or when the
  /// OpenShift read failed; the rest of the summary stands either way.
  final FleetOcpSummary? ocp;

  /// Same summary with [names] as the cached node list.
  FleetK8sSummary withNodes(List<String> names) => FleetK8sSummary(
        read: read,
        apiReachable: apiReachable,
        nodesReady: nodesReady,
        nodesTotal: nodesTotal,
        failedWorkloads: failedWorkloads,
        warningWorkloads: warningWorkloads,
        nodes: names,
        ocp: ocp,
      );

  FleetK8sSummary withOcp(FleetOcpSummary? value) => FleetK8sSummary(
        read: read,
        apiReachable: apiReachable,
        nodesReady: nodesReady,
        nodesTotal: nodesTotal,
        failedWorkloads: failedWorkloads,
        warningWorkloads: warningWorkloads,
        nodes: nodes,
        ocp: value,
      );

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
      nodes: [for (final n in cluster.nodes) n.name],
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
        if (nodes.isNotEmpty) 'nodes': nodes,
        if (ocp != null) 'ocp': ocp!.toJson(),
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
        nodes: [
          if (m['nodes'] is List)
            for (final v in m['nodes'] as List)
              if (v is String) v,
        ],
        ocp: FleetOcpSummary.fromJson(m['ocp']),
      );
    } on FormatException {
      return null;
    }
  }
}


/// M48 §5: what fleet keeps of an OpenShift read.
class FleetOcpSummary {
  const FleetOcpSummary({
    this.version = '',
    this.operatorsDegraded = 0,
    this.operatorsUnavailable = 0,
    this.poolsDegraded = 0,
    this.pendingCsrs = 0,
    this.versionFailing = false,
    this.poolsPaused = 0,
    this.distro,
  });

  factory FleetOcpSummary.from(OpenShiftHealth h) {
    return FleetOcpSummary(
      version: h.version?.version ?? '',
      operatorsDegraded: h.operatorsDegraded,
      operatorsUnavailable: h.operatorsUnavailable,
      poolsDegraded: h.poolsDegraded,
      pendingCsrs: h.csrs?.count ?? 0,
      versionFailing: h.version?.failing ?? false,
      poolsPaused: (h.pools ?? const []).where((p) => p.paused).length,
      distro: h.version?.distro,
    );
  }

  final String version;
  final int operatorsDegraded;
  final int operatorsUnavailable;
  final int poolsDegraded;
  final int pendingCsrs;
  final bool versionFailing;
  final int poolsPaused;

  /// M48.1: OKD vs OCP from the ClusterVersion; null = unknown (reads OCP).
  final OpenShiftDistro? distro;

  bool get isOkd => distro == OpenShiftDistro.okd;

  /// `OKD` with evidence, else `OCP`.
  String get prefix => isOkd ? 'OKD' : 'OCP';

  /// Failed per the M48 §2d table; warning for paused pools / pending CSRs.
  bool get failed =>
      versionFailing ||
      operatorsDegraded > 0 ||
      operatorsUnavailable > 0 ||
      poolsDegraded > 0;

  bool get attention => !failed && (pendingCsrs > 0 || poolsPaused > 0);

  HealthStatus get health => failed
      ? HealthStatus.failed
      : attention
          ? HealthStatus.warning
          : HealthStatus.healthy;

  /// `OCP 4.17.3 · 2 operators degraded`, or `OCP 4.17.3` when healthy.
  String get tileLine {
    String n(int count, String one) =>
        '$count $one${count == 1 ? '' : 's'}';
    return [
      version.isEmpty ? prefix : '$prefix $version',
      if (versionFailing) 'version failing',
      if (operatorsDegraded > 0) '${n(operatorsDegraded, 'operator')} degraded',
      if (operatorsUnavailable > 0)
        '${n(operatorsUnavailable, 'operator')} unavailable',
      if (poolsDegraded > 0) '${n(poolsDegraded, 'pool')} degraded',
      if (poolsPaused > 0) '${n(poolsPaused, 'pool')} paused',
      if (pendingCsrs > 0) '${n(pendingCsrs, 'CSR')} pending',
    ].join(' · ');
  }

  /// Short value for the tile's `ocp` cell (3-column phone grid).
  String get tileValue {
    final ops = operatorsDegraded + operatorsUnavailable;
    if (ops > 0) {
      return '$ops op deg';
    }
    if (poolsDegraded > 0) {
      return '$poolsDegraded mcp deg';
    }
    if (versionFailing) {
      return 'failing';
    }
    if (pendingCsrs > 0) {
      return '$pendingCsrs csr';
    }
    if (poolsPaused > 0) {
      return 'mcp paused';
    }
    return version.isEmpty ? 'ok' : version;
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'opDeg': operatorsDegraded,
        'opUnavail': operatorsUnavailable,
        'mcpDeg': poolsDegraded,
        'csr': pendingCsrs,
        'cvFail': versionFailing,
        'mcpPaused': poolsPaused,
        if (distro != null) 'd': distro!.name,
      };

  static FleetOcpSummary? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    int n(Object? v) => v is int ? v : 0;
    return FleetOcpSummary(
      version: raw['v'] is String ? raw['v'] as String : '',
      operatorsDegraded: n(raw['opDeg']),
      operatorsUnavailable: n(raw['opUnavail']),
      poolsDegraded: n(raw['mcpDeg']),
      pendingCsrs: n(raw['csr']),
      versionFailing: raw['cvFail'] == true,
      poolsPaused: n(raw['mcpPaused']),
      distro: [
        for (final d in OpenShiftDistro.values)
          if (d.name == raw['d']) d,
      ].firstOrNull,
    );
  }
}
