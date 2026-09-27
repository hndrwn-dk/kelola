import 'package:kelola/domain/k8s/workload.dart';

bool workloadCanRestart(K8sKind kind) =>
    kind == K8sKind.deployment ||
    kind == K8sKind.statefulSet ||
    kind == K8sKind.daemonSet;

bool workloadCanScale(K8sKind kind) =>
    kind == K8sKind.deployment || kind == K8sKind.statefulSet;

bool workloadCanDelete(K8sKind kind) => true;

bool workloadCanLogs(K8sKind kind) => true;

bool workloadCanExec(K8sKind kind) => kind == K8sKind.pod;

int nextScaleUp(int desired) => desired + 1;

int nextScaleDown(int desired) => desired <= 0 ? 0 : desired - 1;
