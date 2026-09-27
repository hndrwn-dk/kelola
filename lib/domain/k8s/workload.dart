import 'package:kelola/design/kelola_theme.dart';

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
  });

  final K8sKind kind;
  final String namespace;
  final String name;
  final int ready;
  final int desired;
  final String phase;
  final HealthStatus health;

  String get readyLabel => '$ready/$desired';

  String get title => '$namespace/$name';

  bool get notReady =>
      health == HealthStatus.failed ||
      health == HealthStatus.warning ||
      (desired > 0 && ready < desired);

  K8sWorkload copyWith({int? ready, int? desired, HealthStatus? health}) {
    return K8sWorkload(
      kind: kind,
      namespace: namespace,
      name: name,
      ready: ready ?? this.ready,
      desired: desired ?? this.desired,
      phase: phase,
      health: health ?? this.health,
    );
  }
}

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
