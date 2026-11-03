import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_policy.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_config.dart';
import 'package:kelola/domain/k8s/workload_parser.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';

const _workloads = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Deployment",
      "metadata": {"name": "api", "namespace": "shop"},
      "spec": {
        "replicas": 1,
        "template": {"spec": {
          "serviceAccountName": "api",
          "imagePullSecrets": [{"name": "regcred"}],
          "initContainers": [{"name": "migrate", "image": "acme/api:1.4.2"}],
          "containers": [{
            "name": "api",
            "image": "ghcr.io/acme/api:1.4.2",
            "envFrom": [{"configMapRef": {"name": "api-env"}}],
            "env": [
              {"name": "DB_PASS", "valueFrom": {"secretKeyRef": {"name": "api-db", "key": "password"}}},
              {"name": "FLAG", "valueFrom": {"configMapKeyRef": {"name": "flags", "key": "x", "optional": true}}},
              {"name": "PLAIN", "value": "not-a-ref"}
            ],
            "resources": {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"memory": "256Mi"}},
            "readinessProbe": {"httpGet": {"path": "/ready", "port": 8080}}
          }],
          "volumes": [
            {"name": "db", "secret": {"secretName": "api-db"}},
            {"name": "cfg", "projected": {"sources": [{"configMap": {"name": "api-files"}}]}}
          ]
        }}
      },
      "status": {"replicas": 1, "readyReplicas": 1}
    },
    {
      "kind": "Pod",
      "metadata": {"name": "api-6d4-x", "namespace": "shop",
                   "ownerReferences": [{"kind": "ReplicaSet", "name": "api-6d4"}]},
      "spec": {"containers": [{"name": "api", "image": "ghcr.io/acme/api:1.4.2"}]},
      "status": {"phase": "Running", "containerStatuses": [{"ready": true}]}
    },
    {
      "kind": "DaemonSet",
      "metadata": {"name": "agent", "namespace": "monitoring"},
      "spec": {"template": {"spec": {
        "hostNetwork": true,
        "hostPID": true,
        "containers": [{"name": "agent", "image": "acme/agent",
                        "securityContext": {"privileged": true}}]
      }}},
      "status": {"desiredNumberScheduled": 1, "numberReady": 1}
    },
    {
      "kind": "CronJob",
      "metadata": {"name": "report", "namespace": "shop"},
      "spec": {"jobTemplate": {"spec": {"template": {"spec": {
        "containers": [{"name": "report", "image": "acme/report:latest",
                        "resources": {"requests": {"cpu": "50m"}, "limits": {"memory": "64Mi"}}}]
      }}}}},
      "status": {}
    },
    {
      "kind": "DaemonSet",
      "metadata": {"name": "kube-proxy", "namespace": "kube-system"},
      "spec": {"template": {"spec": {"containers": [{"name": "kube-proxy", "image": "k8s/kube-proxy"}]}}},
      "status": {"desiredNumberScheduled": 1, "numberReady": 1}
    }
  ]
}
''';

void main() {
  final rows = parseWorkloadList(_workloads).rows;
  K8sWorkload row(String name) => rows.firstWhere((r) => r.name == name);

  test('pod template parse: refs dedupe, resources, probes, ownership', () {
    final api = row('api').config!;
    expect(api.serviceAccount, 'api');
    expect(api.ownedByController, isFalse);
    expect(
      api.refs.map((r) => '${r.kind}:${r.name}:${r.optional}').toList()..sort(),
      [
        'ConfigMap:api-env:false',
        'ConfigMap:api-files:false',
        'ConfigMap:flags:true',
        'Secret:api-db:false',
        'Secret:regcred:true',
      ],
      reason: 'api-db is used by env and a volume but listed once',
    );
    final c = api.appContainers.single;
    expect(c.name, 'api');
    expect(c.hasRequests, isTrue);
    expect(c.hasMemoryLimit, isTrue);
    expect(c.readinessProbe, isTrue);
    expect(c.resourcesLabel, 'cpu 100m/- · mem 128Mi/256Mi');
    expect(api.containers.where((c) => c.init).single.name, 'migrate');

    expect(row('api-6d4-x').config!.ownedByController, isTrue);

    final agent = row('agent').config!;
    expect(agent.anyPrivileged, isTrue);
    expect(agent.hostNetwork, isTrue);
    expect(agent.hostPid, isTrue);

    expect(row('report').config!.containers.single.image, 'acme/report:latest');
  });

  test('config findings: missing refs fail, hygiene warns, kube-* skipped', () {
    final inv = parseConfigInventory('''
---CM---
shop|api-env|A,B,|
shop|other||
---SECRET---
shop|regcred|kubernetes.io/dockerconfigjson|.dockerconfigjson,
''');
    expect(inv.configMapCount, 2);
    expect(inv.secrets.single.keys, ['.dockerconfigjson']);

    final findings = configFindings(rows, inv);
    final bySubject = {for (final f in findings) f.subject: f};

    final api = bySubject['deploy shop/api']!;
    expect(api.health, HealthStatus.failed);
    expect(api.issues, [
      'missing Secret api-db',
      'missing ConfigMap api-files',
    ], reason: 'optional flags + regcred never fail; api-env exists');

    final agent = bySubject['ds monitoring/agent']!;
    expect(agent.health, HealthStatus.warning);
    expect(agent.issues, [
      'no requests: agent',
      'no memory limit: agent',
      'no readiness probe: agent',
      ':latest image: agent',
    ]);

    final report = bySubject['cron shop/report']!;
    expect(report.issues, [':latest image: report'],
        reason: 'jobs are not judged on readiness probes');

    expect(bySubject.keys, isNot(contains('ds kube-system/kube-proxy')));
    expect(bySubject.keys, isNot(contains('pod shop/api-6d4-x')),
        reason: 'owned pods are judged on their controller');
    expect(findings.first.subject, 'deploy shop/api', reason: 'failed first');
  });

  test('unreadable Secrets skip secret checks instead of flagging all', () {
    final inv = parseConfigInventory('''
---CM---
shop|api-env||
shop|api-files||
---SECRET---
---SECRET_FAIL---
''');
    expect(inv.configMapsReadable, isTrue);
    expect(inv.secretsReadable, isFalse);
    final api = configFindings(rows, inv)
        .where((f) => f.subject == 'deploy shop/api');
    expect(api, isEmpty);
  });

  test('security inventory: system subjects ignored, netpol by namespace', () {
    final sec = parseSecurityInventory(r'''
{"kind": "List", "items": [
  {"kind": "ServiceAccount", "metadata": {"name": "default", "namespace": "shop"}},
  {"kind": "ServiceAccount", "metadata": {"name": "api", "namespace": "shop"}},
  {"kind": "NetworkPolicy", "metadata": {"name": "deny", "namespace": "monitoring"}},
  {"kind": "ClusterRoleBinding", "metadata": {"name": "cluster-admin"},
   "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
   "subjects": [{"kind": "Group", "name": "system:masters"}]},
  {"kind": "ClusterRoleBinding", "metadata": {"name": "kubeadm:cluster-admins"},
   "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
   "subjects": [{"kind": "Group", "name": "kubeadm:cluster-admins"}]},
  {"kind": "ClusterRoleBinding", "metadata": {"name": "ops-admin"},
   "roleRef": {"kind": "ClusterRole", "name": "cluster-admin"},
   "subjects": [{"kind": "User", "name": "alice"},
                {"kind": "ServiceAccount", "name": "ci", "namespace": "build"}]},
  {"kind": "ClusterRoleBinding", "metadata": {"name": "view-all"},
   "roleRef": {"kind": "ClusterRole", "name": "view"},
   "subjects": [{"kind": "User", "name": "bob"}]}
]}
''');
    expect(sec.serviceAccounts, 2);
    expect(sec.networkPolicyNamespaces, {'monitoring'});
    expect(
      sec.clusterAdminGrants.map((g) => '${g.binding}: ${g.subject}').toList(),
      ['ops-admin: User alice', 'ops-admin: ServiceAccount build/ci'],
    );

    final findings = securityFindings(rows, sec);
    final subjects = findings.map((f) => f.subject).toList();
    expect(subjects, contains('ds monitoring/agent'));
    expect(
      findings.firstWhere((f) => f.subject == 'ds monitoring/agent').issues,
      ['privileged: agent', 'hostNetwork', 'hostPID'],
    );
    expect(subjects, contains('namespace shop'));
    expect(subjects, isNot(contains('namespace monitoring')),
        reason: 'monitoring has a NetworkPolicy');
    expect(subjects, isNot(contains('namespace kube-system')));
    expect(subjects.where((s) => s == 'ClusterRoleBinding ops-admin'),
        hasLength(2));
  });

  test('config probe never prints Secret values', () {
    expect(ConfigInventoryProbe.secretTemplate, isNot(contains(r'{{$v}}')));
    expect(ConfigInventoryProbe.configMapTemplate, isNot(contains(r'{{$v}}')));
    // Keys are ranged over; values ($v) and whole maps ({{.data}}) never
    // reach the output.
    expect(ConfigInventoryProbe.secretTemplate, isNot(contains(r'{{$v')));
    expect(ConfigInventoryProbe.secretTemplate, isNot(contains('{{.data')));
    final cmd = const ConfigInventoryProbe()
        .command(HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']));
    expect(cmd, contains('get secrets -A -o go-template='));
    expect(cmd, isNot(contains('-o json')));
    expect(cmd, contains('---SECRET_FAIL---'));
  });

  test('config probe: both sections failing is a read error', () {
    expect(
      () => const ConfigInventoryProbe().parse(
        '---CM---\n---CM_FAIL---\n---SECRET---\n---SECRET_FAIL---\n',
        'Error from server (Forbidden)',
        0,
      ),
      throwsA(isA<K8sReadException>()),
    );
  });

  test('containerHygieneOk matches the Configuration rules', () {
    K8sWorkload w(String ns, {K8sKind kind = K8sKind.deployment}) =>
        K8sWorkload(kind: kind, namespace: ns, name: 'x', ready: 1, desired: 1);
    const tidy = K8sContainerConfig(
      name: 'app',
      image: 'acme/app:1.2.3',
      cpuRequest: '100m',
      memoryRequest: '64Mi',
      memoryLimit: '128Mi',
      readinessProbe: true,
    );
    const bare = K8sContainerConfig(name: 'app', image: 'acme/app:1.2.3');
    const latest = K8sContainerConfig(
      name: 'app',
      image: 'acme/app:latest',
      cpuRequest: '100m',
      memoryRequest: '64Mi',
      memoryLimit: '128Mi',
      readinessProbe: true,
    );
    const noProbe = K8sContainerConfig(
      name: 'job',
      image: 'acme/job:1',
      cpuRequest: '100m',
      memoryRequest: '64Mi',
      memoryLimit: '128Mi',
    );
    expect(containerHygieneOk(w('shop'), tidy), isTrue);
    expect(containerHygieneOk(w('shop'), bare), isFalse);
    expect(containerHygieneOk(w('shop'), latest), isFalse);
    // kube-* add-ons are not judged, same as the Configuration section.
    expect(containerHygieneOk(w('kube-system'), bare), isTrue);
    // Jobs need no readiness probe.
    expect(containerHygieneOk(w('shop'), noProbe), isFalse);
    expect(containerHygieneOk(w('shop', kind: K8sKind.job), noProbe), isTrue);
  });
}
