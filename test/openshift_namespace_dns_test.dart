import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/bulk_restart.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_home_summary.dart';

K8sWorkload _pod(String ns, String name, {bool ready = true}) => K8sWorkload(
      kind: K8sKind.pod,
      namespace: ns,
      name: name,
      ready: ready ? 1 : 0,
      desired: 1,
      phase: ready ? 'Running' : 'Pending',
      health: ready ? HealthStatus.healthy : HealthStatus.warning,
    );

K8sWorkload _deploy(String ns, String name) => K8sWorkload(
      kind: K8sKind.deployment,
      namespace: ns,
      name: name,
      ready: 1,
      desired: 1,
      health: HealthStatus.healthy,
    );

void main() {
  group('isSystemNamespace (M48 §2e)', () {
    test('kube-*, openshift and openshift-* are platform', () {
      for (final ns in [
        'kube-system',
        'kube-public',
        'openshift',
        'openshift-dns',
        'openshift-monitoring',
        'openshift-machine-config-operator',
      ]) {
        expect(isSystemNamespace(ns), isTrue, reason: ns);
      }
    });

    test('operator namespaces are not', () {
      for (final ns in [
        'default',
        'prod',
        'openshiftish',
        'my-openshift-app',
        'kubeflow',
      ]) {
        expect(isSystemNamespace(ns), isFalse, reason: ns);
      }
    });

    test('bulk restart lists openshift-* last and unchecked', () {
      final order = bulkRestartNamespaces([
        _deploy('openshift-console', 'console'),
        _deploy('prod', 'web'),
        _deploy('kube-system', 'metrics'),
        _deploy('apps', 'api'),
      ]);
      expect(order, ['apps', 'prod', 'kube-system', 'openshift-console']);
      expect(bulkRestartCheckedByDefault('openshift-console'), isFalse);
      expect(bulkRestartCheckedByDefault('openshift'), isFalse);
      expect(bulkRestartCheckedByDefault('prod'), isTrue);
    });
  });

  group('DNS readiness (M48 §2e)', () {
    test('OpenShift dns-default pods in openshift-dns count', () {
      expect(
        coreDnsReadyFromWorkloads([_pod('openshift-dns', 'dns-default-x7k2p')]),
        isTrue,
      );
      expect(
        coreDnsReadyFromWorkloads([
          _pod('openshift-dns', 'dns-default-a'),
          _pod('openshift-dns', 'dns-default-b', ready: false),
        ]),
        isFalse,
      );
    });

    test('node-resolver and other namespaces do not', () {
      expect(
        coreDnsReadyFromWorkloads([
          _pod('openshift-dns', 'node-resolver-abc'),
          _pod('prod', 'dns-default-imposter'),
        ]),
        isNull,
      );
    });

    test('CoreDNS in kube-system still counts', () {
      expect(
        coreDnsReadyFromWorkloads([_pod('kube-system', 'coredns-5d78c9869d-x')]),
        isTrue,
      );
    });
  });
}
