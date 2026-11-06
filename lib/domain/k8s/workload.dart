import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/workload_config.dart';

enum K8sKind {
  deployment,
  statefulSet,
  daemonSet,
  job,
  cronJob,
  pod;

  String get resource => switch (this) {
    K8sKind.deployment => 'deployment',
    K8sKind.statefulSet => 'statefulset',
    K8sKind.daemonSet => 'daemonset',
    K8sKind.job => 'job',
    K8sKind.cronJob => 'cronjob',
    K8sKind.pod => 'pod',
  };

  String get short => switch (this) {
    K8sKind.deployment => 'deploy',
    K8sKind.statefulSet => 'sts',
    K8sKind.daemonSet => 'ds',
    K8sKind.job => 'job',
    K8sKind.cronJob => 'cron',
    K8sKind.pod => 'pod',
  };
}

K8sKind? parseK8sKind(String? kind) {
  return switch (kind) {
    'Deployment' => K8sKind.deployment,
    'StatefulSet' => K8sKind.statefulSet,
    'DaemonSet' => K8sKind.daemonSet,
    'Job' => K8sKind.job,
    'CronJob' => K8sKind.cronJob,
    'Pod' => K8sKind.pod,
    _ => null,
  };
}

class K8sWorkload {
  const K8sWorkload({
    required this.kind,
    required this.namespace,
    required this.name,
    required this.ready,
    required this.desired,
    this.phase = '',
    this.health = HealthStatus.unknown,
    this.restarts = 0,
    this.podPhase = '',
    this.config,
  });

  final K8sKind kind;
  final String namespace;
  final String name;
  final int ready;
  final int desired;
  final String phase;
  final HealthStatus health;

  /// Pods only: sum of container + init container restartCount.
  final int restarts;

  /// Pods only: raw `status.phase` (Pending/Running/Succeeded/Failed).
  /// [phase] is the display string and may carry a waiting reason instead.
  final String podPhase;

  /// Pod template (controllers) or pod spec (Pods). Null when the JSON had
  /// no spec, e.g. rows built in tests.
  final K8sPodConfig? config;

  String get readyLabel => '$ready/$desired';

  String get title => '$namespace/$name';

  /// Completed pods (Succeeded) are healthy with 0/N ready containers;
  /// they must not count as not ready.
  bool get notReady =>
      !readyButRestarting &&
      (health == HealthStatus.failed ||
          health == HealthStatus.warning ||
          (health == HealthStatus.unknown && desired > 0 && ready < desired));

  /// A running pod with every container ready, flagged only for its lifetime
  /// restart count (a node reboot adds to it). Worth a warning, but ready.
  bool get readyButRestarting =>
      kind == K8sKind.pod &&
      health == HealthStatus.warning &&
      podPhase == 'Running' &&
      desired > 0 &&
      ready >= desired;

  bool get pending =>
      kind == K8sKind.pod &&
      (podPhase == 'Pending' || (podPhase.isEmpty && phase == 'Pending'));

  bool get crashLooping =>
      kind == K8sKind.pod && phase.endsWith('CrashLoopBackOff');

  bool get restarting => kind == K8sKind.pod && restarts >= kRestartWarn;

  K8sWorkload copyWith({int? ready, int? desired, HealthStatus? health}) {
    return K8sWorkload(
      kind: kind,
      namespace: namespace,
      name: name,
      ready: ready ?? this.ready,
      desired: desired ?? this.desired,
      phase: phase,
      health: health ?? this.health,
      restarts: restarts,
      podPhase: podPhase,
      config: config,
    );
  }
}

/// A running, ready pod with at least this many restarts is a warning:
/// it is flapping even if the last probe happened to pass.
const kRestartWarn = 5;

class WorkloadInventory {
  const WorkloadInventory({
    required this.rows,
    this.missingKubectl = false,
  });

  final List<K8sWorkload> rows;
  final bool missingKubectl;
}

class K8sEvent {
  const K8sEvent({
    required this.type,
    required this.reason,
    required this.message,
    this.when = '',
  });

  final String type;
  final String reason;
  final String message;
  final String when;
}

class K8sTopRow {
  const K8sTopRow({
    required this.name,
    required this.cpu,
    required this.memory,
  });

  final String name;
  final String cpu;
  final String memory;
}
