import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';

/// M48: OpenShift-only cluster state, read by `OpenShiftHealthProbe` on top
/// of the Kubernetes home reads. Read-only; nothing here mutates the cluster.
enum OcpSection { clusterVersion, clusterOperators, machineConfigPools, csrs }

extension OcpSectionLabel on OcpSection {
  /// Human noun for `Could not read …`.
  String get what => switch (this) {
        OcpSection.clusterVersion => 'cluster version',
        OcpSection.clusterOperators => 'cluster operators',
        OcpSection.machineConfigPools => 'machine config pools',
        OcpSection.csrs => 'CSRs',
      };
}

/// One status condition. [status] is null when the condition is absent or
/// its status is `Unknown`.
class OcpCondition {
  const OcpCondition({
    required this.type,
    required this.status,
    this.reason = '',
    this.message = '',
  });

  final String type;
  final bool? status;
  final String reason;
  final String message;

  String get statusLabel => switch (status) {
        true => 'True',
        false => 'False',
        null => 'Unknown',
      };
}

class ClusterVersionState {
  const ClusterVersionState({
    required this.version,
    this.channel = '',
    this.progressing = false,
    this.progressingMessage = '',
    this.failing = false,
    this.failingMessage = '',
    this.availableUpdates = 0,
    this.overrides = 0,
  });

  /// `status.desired.version`.
  final String version;

  /// `spec.channel`, e.g. `stable-4.17`.
  final String channel;
  final bool progressing;
  final String progressingMessage;
  final bool failing;
  final String failingMessage;

  /// `len(status.availableUpdates)`.
  final int availableUpdates;

  /// `len(spec.overrides)`: components the CVO no longer manages.
  final int overrides;
}

class ClusterOperatorState {
  const ClusterOperatorState({
    required this.name,
    this.version = '',
    this.available,
    this.progressing,
    this.degraded,
    this.conditions = const [],
  });

  final String name;

  /// `status.versions[name=operator].version`.
  final String version;
  final bool? available;
  final bool? progressing;
  final bool? degraded;

  /// Available, Progressing, Degraded — in that order, when present.
  final List<OcpCondition> conditions;

  bool get isUnavailable => available == false;
  bool get isDegraded => degraded == true;
  bool get isProgressing => progressing == true;

  /// `Available=False` or `Degraded=True` is failed. Progressing is a fact.
  HealthStatus get health {
    if (isUnavailable || isDegraded) {
      return HealthStatus.failed;
    }
    if (available == null) {
      return HealthStatus.unknown;
    }
    return HealthStatus.healthy;
  }

  OcpCondition? condition(String type) {
    for (final c in conditions) {
      if (c.type == type) {
        return c;
      }
    }
    return null;
  }

  /// Row meta: `4.17.3 · degraded · progressing`.
  String get meta {
    return [
      if (version.isNotEmpty) version,
      if (isUnavailable) 'unavailable',
      if (isDegraded) 'degraded',
      if (isProgressing) 'progressing',
      if (!isUnavailable && !isDegraded && !isProgressing && available == true)
        'available',
    ].join(' · ');
  }
}

class MachineConfigPoolState {
  const MachineConfigPoolState({
    required this.name,
    this.machineCount = 0,
    this.readyMachineCount = 0,
    this.updatedMachineCount = 0,
    this.degradedMachineCount = 0,
    this.paused = false,
    this.degraded = false,
    this.degradedMessage = '',
    this.updating = false,
    this.updatingMessage = '',
    this.nodeSelector = const {},
  });

  final String name;
  final int machineCount;
  final int readyMachineCount;
  final int updatedMachineCount;
  final int degradedMachineCount;

  /// `spec.paused`: blocks kubelet certificate rotation.
  final bool paused;
  final bool degraded;
  final String degradedMessage;
  final bool updating;
  final String updatingMessage;

  /// `spec.nodeSelector.matchLabels`, matched against nodes already read.
  final Map<String, String> nodeSelector;

  bool get isDegraded => degraded || degradedMachineCount > 0;

  bool get fullyUpdated =>
      machineCount > 0 && updatedMachineCount >= machineCount;

  HealthStatus get health {
    if (isDegraded) {
      return HealthStatus.failed;
    }
    if (paused) {
      return HealthStatus.warning;
    }
    return HealthStatus.healthy;
  }

  /// `2/3 updated · 1 degraded · paused · updating`.
  String get meta {
    return [
      '$updatedMachineCount/$machineCount updated',
      '$readyMachineCount ready',
      if (degradedMachineCount > 0) '$degradedMachineCount degraded',
      if (degraded && degradedMachineCount == 0) 'degraded',
      if (paused) 'paused',
      if (updating) 'updating',
    ].join(' · ');
  }

  /// A node is in the pool when every selector label matches. An empty
  /// selector matches nothing (never "every node").
  bool selects(ClusterNodeMembership node) {
    if (nodeSelector.isEmpty) {
      return false;
    }
    for (final e in nodeSelector.entries) {
      if (node.labels[e.key] != e.value) {
        return false;
      }
    }
    return true;
  }
}

class PendingCsrs {
  const PendingCsrs({required this.count, this.usernames = const []});

  final int count;

  /// `spec.username` of each pending request, in order.
  final List<String> usernames;
}

class OcpFinding {
  const OcpFinding({
    required this.subject,
    required this.message,
    required this.health,
  });

  final String subject;
  final String message;

  /// failed or warning only.
  final HealthStatus health;
}

class OpenShiftHealth {
  const OpenShiftHealth({
    this.version,
    this.operators,
    this.pools,
    this.csrs,
    this.sectionErrors = const {},
    this.nodes = const [],
  });

  final ClusterVersionState? version; // null = unreadable
  final List<ClusterOperatorState>? operators;
  final List<MachineConfigPoolState>? pools;
  final PendingCsrs? csrs;

  /// Section → reason (`Forbidden`), for every section that printed no JSON.
  final Map<OcpSection, String> sectionErrors;

  /// Nodes from the cluster read, for node MCD findings. Not read here.
  final List<ClusterNodeMembership> nodes;

  OpenShiftHealth withNodes(List<ClusterNodeMembership> nodes) {
    return OpenShiftHealth(
      version: version,
      operators: operators,
      pools: pools,
      csrs: csrs,
      sectionErrors: sectionErrors,
      nodes: nodes,
    );
  }

  /// `Could not read CSRs: Forbidden`.
  String? errorFor(OcpSection section) {
    final reason = sectionErrors[section];
    if (reason == null) {
      return null;
    }
    return reason.isEmpty
        ? 'Could not read ${section.what}'
        : 'Could not read ${section.what}: $reason';
  }

  int get operatorsDegraded =>
      (operators ?? const []).where((o) => o.isDegraded).length;

  int get operatorsUnavailable =>
      (operators ?? const []).where((o) => o.isUnavailable).length;

  int get operatorsProgressing =>
      (operators ?? const []).where((o) => o.isProgressing).length;

  int get operatorsHealthy => (operators ?? const [])
      .where((o) => o.health == HealthStatus.healthy)
      .length;

  int get poolsDegraded =>
      (pools ?? const []).where((p) => p.isDegraded).length;

  int get poolsUpdated => (pools ?? const []).where((p) => p.fullyUpdated).length;

  List<ClusterNodeMembership> get degradedNodes => [
        for (final n in nodes)
          if (n.mcdState == McdState.degraded) n,
      ];

  /// M48 §2d. Progressing / updating / available updates / overrides are
  /// facts, not findings. `Upgradeable=False` is ignored.
  List<OcpFinding> get findings {
    final out = <OcpFinding>[];
    final v = version;
    if (v != null && v.failing) {
      out.add(
        OcpFinding(
          subject: 'ClusterVersion',
          message: v.failingMessage.isEmpty ? 'Failing' : v.failingMessage,
          health: HealthStatus.failed,
        ),
      );
    }
    for (final o in operators ?? const <ClusterOperatorState>[]) {
      if (o.isUnavailable) {
        out.add(
          OcpFinding(
            subject: o.name,
            message: _condText(o.condition('Available'), 'not available'),
            health: HealthStatus.failed,
          ),
        );
      }
      if (o.isDegraded) {
        out.add(
          OcpFinding(
            subject: o.name,
            message: _condText(o.condition('Degraded'), 'degraded'),
            health: HealthStatus.failed,
          ),
        );
      }
    }
    for (final p in pools ?? const <MachineConfigPoolState>[]) {
      if (p.isDegraded) {
        out.add(
          OcpFinding(
            subject: 'pool ${p.name}',
            message: p.degradedMessage.isNotEmpty
                ? p.degradedMessage
                : '${p.degradedMachineCount} machines degraded',
            health: HealthStatus.failed,
          ),
        );
      }
    }
    for (final n in degradedNodes) {
      out.add(
        OcpFinding(
          subject: 'node ${n.name}',
          message: n.mcdReason.isEmpty ? 'MCD degraded' : n.mcdReason,
          health: HealthStatus.failed,
        ),
      );
    }
    for (final p in pools ?? const <MachineConfigPoolState>[]) {
      if (p.paused) {
        out.add(
          OcpFinding(
            subject: 'pool ${p.name}',
            message: 'paused; blocks kubelet certificate rotation',
            health: HealthStatus.warning,
          ),
        );
      }
    }
    final c = csrs;
    if (c != null && c.count > 0) {
      out.add(
        OcpFinding(
          subject: '${c.count} pending CSR${c.count == 1 ? '' : 's'}',
          message: c.usernames.take(3).join(', '),
          health: HealthStatus.warning,
        ),
      );
    }
    return out;
  }

  /// Own overall; the home band shows the worse of this and the cluster's.
  /// Any unreadable section keeps a clean result from reading as healthy.
  HealthStatus get overall {
    final f = findings;
    if (f.any((x) => x.health == HealthStatus.failed)) {
      return HealthStatus.failed;
    }
    if (f.any((x) => x.health == HealthStatus.warning)) {
      return HealthStatus.warning;
    }
    if (sectionErrors.isNotEmpty ||
        version == null ||
        operators == null ||
        pools == null ||
        csrs == null) {
      return HealthStatus.unknown;
    }
    return HealthStatus.healthy;
  }

  /// RiskBand headline: `2 operators degraded · 1 pool paused`.
  String get summary {
    final parts = <String>[
      if (version?.failing == true) 'cluster version failing',
      if (operatorsDegraded > 0)
        '$operatorsDegraded operator${operatorsDegraded == 1 ? '' : 's'} degraded',
      if (operatorsUnavailable > 0)
        '$operatorsUnavailable operator${operatorsUnavailable == 1 ? '' : 's'} unavailable',
      if (poolsDegraded > 0)
        '$poolsDegraded pool${poolsDegraded == 1 ? '' : 's'} degraded',
      if (degradedNodes.isNotEmpty)
        '${degradedNodes.length} node${degradedNodes.length == 1 ? '' : 's'} degraded',
      if ((pools ?? const []).any((p) => p.paused))
        '${pools!.where((p) => p.paused).length} pool${pools!.where((p) => p.paused).length == 1 ? '' : 's'} paused',
      if ((csrs?.count ?? 0) > 0)
        '${csrs!.count} CSR${csrs!.count == 1 ? '' : 's'} pending',
    ];
    if (parts.isNotEmpty) {
      return parts.join(' · ');
    }
    if (overall == HealthStatus.unknown) {
      return 'Some OpenShift sections could not be read';
    }
    return 'Operators, pools and nodes healthy';
  }

  /// Operators `31/33 healthy`, or `unknown`.
  String get operatorsLabel {
    final list = operators;
    if (list == null) {
      return 'unknown';
    }
    return '$operatorsHealthy/${list.length} healthy';
  }

  /// Pools `2/2 updated`, or `unknown`.
  String get poolsLabel {
    final list = pools;
    if (list == null) {
      return 'unknown';
    }
    return '$poolsUpdated/${list.length} updated';
  }

  /// CSRs `0 pending`, or `unknown`.
  String get csrsLabel {
    final c = csrs;
    if (c == null) {
      return 'unknown';
    }
    return '${c.count} pending';
  }
}

String _condText(OcpCondition? c, String fallback) {
  if (c == null) {
    return fallback;
  }
  final parts = [
    if (c.reason.isNotEmpty) c.reason,
    if (c.message.isNotEmpty) c.message,
  ];
  return parts.isEmpty ? fallback : parts.join(': ');
}

/// Worse of two health states for the home band. Unknown only wins when
/// neither side knows; a known failure is never hidden by an unknown.
HealthStatus worseHealth(HealthStatus a, HealthStatus b) {
  int rank(HealthStatus h) => switch (h) {
        HealthStatus.failed => 3,
        HealthStatus.warning => 2,
        HealthStatus.healthy => 1,
        HealthStatus.unknown => 0,
      };
  if (a == HealthStatus.unknown && b == HealthStatus.unknown) {
    return HealthStatus.unknown;
  }
  return rank(a) >= rank(b) ? a : b;
}

/// Operator chips on the OpenShift section.
enum OcpOperatorFilter { all, degraded, unavailable, progressing }

extension OcpOperatorFilterView on OcpOperatorFilter {
  String get label => switch (this) {
        OcpOperatorFilter.all => 'All',
        OcpOperatorFilter.degraded => 'Degraded',
        OcpOperatorFilter.unavailable => 'Unavailable',
        OcpOperatorFilter.progressing => 'Progressing',
      };

  bool matches(ClusterOperatorState op) => switch (this) {
        OcpOperatorFilter.all => true,
        OcpOperatorFilter.degraded => op.isDegraded,
        OcpOperatorFilter.unavailable => op.isUnavailable,
        OcpOperatorFilter.progressing => op.isProgressing,
      };

  int count(List<ClusterOperatorState> ops) => ops.where(matches).length;

  String get emptyCopy => switch (this) {
        OcpOperatorFilter.all => 'No cluster operators',
        OcpOperatorFilter.degraded => 'No degraded operators',
        OcpOperatorFilter.unavailable => 'No unavailable operators',
        OcpOperatorFilter.progressing => 'No operators progressing',
      };
}
