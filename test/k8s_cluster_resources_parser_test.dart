import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/cluster_resources_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_parser.dart';
import 'package:kelola/domain/probes/cluster_resource_probes.dart';

String _rs({
  required String name,
  required int revision,
  required String created,
  required String image,
  String owner = 'web',
  String ownerKind = 'Deployment',
  String restartedAt = '',
  String history = '',
  String cause = '',
  String sidecar = '',
}) {
  final ann = <String>[
    '"deployment.kubernetes.io/revision": "$revision"',
    if (history.isNotEmpty)
      '"deployment.kubernetes.io/revision-history": "$history"',
    if (cause.isNotEmpty) '"kubernetes.io/change-cause": "$cause"',
  ].join(', ');
  final tmplAnn = restartedAt.isEmpty
      ? ''
      : '"annotations": {"kubectl.kubernetes.io/restartedAt": "$restartedAt"}';
  final side =
      sidecar.isEmpty ? '' : ', {"name": "log", "image": "$sidecar"}';
  return '''
{
  "kind": "ReplicaSet",
  "metadata": {
    "name": "$name", "namespace": "shop", "creationTimestamp": "$created",
    "annotations": {$ann},
    "ownerReferences": [{"kind": "$ownerKind", "name": "$owner", "controller": true}]
  },
  "spec": {"template": {"metadata": {$tmplAnn}, "spec": {"containers": [{"name": "web", "image": "$image"}$side]}}}
}''';
}

String _list(List<String> items) =>
    '{"kind": "List", "items": [${items.join(',')}]}';

const _stsRevisions = r'''
{"kind": "List", "items": [
  {"kind": "ControllerRevision", "revision": 2,
   "metadata": {"name": "db-6f", "namespace": "data", "creationTimestamp": "2026-11-02T10:00:00Z",
     "ownerReferences": [{"kind": "StatefulSet", "name": "db", "controller": true}]},
   "data": {"spec": {"template": {"$patch": "replace", "spec": {
     "initContainers": [{"name": "init-perm", "image": "busybox:1.36"}],
     "containers": [{"name": "pg", "image": "postgres:16.4"}]}}}}},
  {"kind": "ControllerRevision", "revision": 1,
   "metadata": {"name": "db-5c", "namespace": "data", "creationTimestamp": "2026-10-20T10:00:00Z",
     "ownerReferences": [{"kind": "StatefulSet", "name": "db", "controller": true}]},
   "data": {"spec": {"template": {"$patch": "replace", "spec": {
     "initContainers": [{"name": "init-perm", "image": "busybox:1.36"}],
     "containers": [{"name": "pg", "image": "postgres:16.2"}]}}}}},
  {"kind": "ControllerRevision", "revision": 1,
   "metadata": {"name": "orphan-1", "namespace": "data", "creationTimestamp": "2026-10-20T10:00:00Z"},
   "data": {"spec": {"template": {"spec": {"containers": [{"name": "x", "image": "x"}]}}}}}
]}
''';

const _events = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Event",
      "metadata": {"name": "a.1", "namespace": "shop"},
      "involvedObject": {"kind": "Pod", "namespace": "shop", "name": "api-7f9"},
      "type": "Warning",
      "reason": "BackOff",
      "message": "Back-off restarting failed container api\n",
      "count": 12,
      "lastTimestamp": "2026-11-02T11:55:00Z"
    },
    {
      "kind": "Event",
      "metadata": {"name": "b.1", "namespace": "kube-system", "creationTimestamp": "2026-11-02T09:00:00Z"},
      "involvedObject": {"kind": "Node", "name": "worker-1"},
      "type": "Warning",
      "reason": "NodeNotReady",
      "message": "Node is not ready",
      "lastTimestamp": null,
      "eventTime": "2026-11-02T10:00:00.000000Z",
      "series": {"count": 3}
    },
    {
      "kind": "Event",
      "metadata": {"name": "c.1", "namespace": "db"},
      "involvedObject": {"kind": "PersistentVolumeClaim", "namespace": "db", "name": "data"},
      "type": "Warning",
      "reason": "ProvisioningFailed",
      "message": "no volume plugin matched"
    }
  ]
}
''';

const _net = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Service",
      "metadata": {"name": "api", "namespace": "shop"},
      "spec": {"type": "ClusterIP", "clusterIP": "10.43.0.10",
               "selector": {"app": "api"},
               "ports": [{"port": 80, "protocol": "TCP"}]}
    },
    {
      "kind": "Service",
      "metadata": {"name": "web", "namespace": "shop"},
      "spec": {"type": "NodePort", "clusterIP": "10.43.0.11",
               "selector": {"app": "web"},
               "ports": [{"port": 80, "nodePort": 30080, "protocol": "TCP"}]}
    },
    {
      "kind": "Service",
      "metadata": {"name": "edge", "namespace": "shop"},
      "spec": {"type": "LoadBalancer", "clusterIP": "10.43.0.12",
               "selector": {"app": "web"},
               "ports": [{"port": 443}]},
      "status": {"loadBalancer": {}}
    },
    {
      "kind": "Service",
      "metadata": {"name": "kubernetes", "namespace": "default"},
      "spec": {"type": "ClusterIP", "clusterIP": "10.43.0.1",
               "ports": [{"port": 443, "protocol": "TCP"}]}
    },
    {
      "kind": "Service",
      "metadata": {"name": "ext", "namespace": "shop"},
      "spec": {"type": "ExternalName", "externalName": "db.example.com"}
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "web", "namespace": "shop"},
      "subsets": [
        {"addresses": [{"ip": "10.42.0.5"}, {"ip": "10.42.0.6"}],
         "notReadyAddresses": [{"ip": "10.42.0.7"}],
         "ports": [{"port": 8080}]},
        {"addresses": [{"ip": "10.42.0.5"}], "ports": [{"port": 9090}]}
      ]
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "edge", "namespace": "shop"},
      "subsets": [{"addresses": [{"ip": "10.42.0.5"}]}]
    }
  ]
}
''';

const _storage = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "PersistentVolume",
      "metadata": {"name": "pvc-123"},
      "spec": {"capacity": {"storage": "10Gi"},
               "claimRef": {"namespace": "db", "name": "pg"},
               "persistentVolumeReclaimPolicy": "Delete",
               "storageClassName": "local-path"},
      "status": {"phase": "Bound"}
    },
    {
      "kind": "PersistentVolume",
      "metadata": {"name": "old-nfs"},
      "spec": {"capacity": {"storage": "50Gi"},
               "claimRef": {"namespace": "x", "name": "gone"},
               "persistentVolumeReclaimPolicy": "Retain"},
      "status": {"phase": "Released"}
    },
    {
      "kind": "PersistentVolumeClaim",
      "metadata": {"name": "pg", "namespace": "db"},
      "spec": {"resources": {"requests": {"storage": "10Gi"}},
               "storageClassName": "local-path", "volumeName": "pvc-123"},
      "status": {"phase": "Bound", "capacity": {"storage": "10Gi"}}
    },
    {
      "kind": "PersistentVolumeClaim",
      "metadata": {"name": "data", "namespace": "db"},
      "spec": {"resources": {"requests": {"storage": "5Gi"}},
               "storageClassName": "fast"},
      "status": {"phase": "Pending"}
    }
  ]
}
''';

void main() {
  test('cluster events: newest first, count from series, message trimmed', () {
    final events = parseClusterEvents(_events);
    expect(events.map((e) => e.reason).toList(),
        ['BackOff', 'NodeNotReady', 'ProvisioningFailed']);
    final backOff = events.first;
    expect(backOff.count, 12);
    expect(backOff.message, 'Back-off restarting failed container api');
    expect(backOff.objectLabel, 'Pod shop/api-7f9');
    expect(backOff.warning, isTrue);
    final node = events[1];
    expect(node.count, 3);
    expect(node.objectLabel, 'Node worker-1');
    expect(node.at, DateTime.utc(2026, 11, 2, 10));
    expect(events.last.at, isNull);
  });

  test('services join endpoints and flag missing / pending', () {
    final net = parseNetworking(_net);
    final byName = {for (final s in net.services) s.name: s};
    expect(byName.keys, containsAll(['api', 'web', 'edge', 'kubernetes', 'ext']));

    final api = byName['api']!;
    expect(api.noEndpoints, isTrue);
    expect(api.health, HealthStatus.failed);
    expect(api.endpointsLabel, '0/0 endpoints');

    final web = byName['web']!;
    expect(web.readyEndpoints, 2, reason: 'IPs dedupe across subsets');
    expect(web.notReadyEndpoints, 1);
    expect(web.ports, '80:30080/TCP');
    expect(web.health, HealthStatus.warning);

    final edge = byName['edge']!;
    expect(edge.loadBalancerPending, isTrue);
    expect(edge.health, HealthStatus.warning);

    // No selector: endpoints are managed by hand / by the API server.
    expect(byName['kubernetes']!.health, HealthStatus.healthy);
    expect(byName['kubernetes']!.endpointsLabel, 'no selector');
    final ext = byName['ext']!;
    expect(ext.health, HealthStatus.healthy);
    expect(ext.externalAddress, 'db.example.com');
    expect(ext.endpointsLabel, 'external');

    expect(net.noEndpointCount, 1);
    expect(net.lbPendingCount, 1);
  });

  test('service detail keeps selector, target ports, and endpoint targets', () {
    const raw = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "Service",
      "metadata": {"name": "web", "namespace": "shop"},
      "spec": {"type": "NodePort", "clusterIP": "10.43.0.11",
               "selector": {"app": "web", "tier": "front"},
               "ports": [
                 {"port": 80, "nodePort": 30080, "protocol": "TCP", "targetPort": "http"},
                 {"port": 9090, "protocol": "TCP", "targetPort": 9090},
                 {"port": 443, "protocol": "TCP", "targetPort": 8443}
               ]}
    },
    {
      "kind": "Endpoints",
      "metadata": {"name": "web", "namespace": "shop"},
      "subsets": [
        {"addresses": [
           {"ip": "10.42.0.5", "nodeName": "node01",
            "targetRef": {"kind": "Pod", "namespace": "shop", "name": "web-a"}},
           {"ip": "10.42.0.9"}
         ],
         "notReadyAddresses": [
           {"ip": "10.42.0.7", "nodeName": "node02",
            "targetRef": {"kind": "Pod", "namespace": "shop", "name": "web-b"}}
         ]},
        {"addresses": [{"ip": "10.42.0.5", "nodeName": "node01",
           "targetRef": {"kind": "Pod", "namespace": "shop", "name": "web-a"}}]}
      ]
    }
  ]
}
''';
    final web = parseNetworking(raw).services.single;
    expect(web.selector, {'app': 'web', 'tier': 'front'});
    expect(web.selectorLabel, 'app=web, tier=front');
    expect(web.portList.map((p) => p.label).toList(),
        ['80:30080/TCP → http', '9090/TCP', '443/TCP → 8443']);

    expect(web.readyEndpoints, 2);
    expect(web.notReadyEndpoints, 1);
    expect(web.addresses, hasLength(3), reason: 'one row per IP');
    final a = web.addresses.firstWhere((e) => e.ip == '10.42.0.5');
    expect(a.ready, isTrue);
    expect(a.nodeName, 'node01');
    expect(a.targetKind, 'Pod');
    expect(a.targetNamespace, 'shop');
    expect(a.targetName, 'web-a');
    final manual = web.addresses.firstWhere((e) => e.ip == '10.42.0.9');
    expect(manual.targetName, isEmpty, reason: 'no targetRef: IP only');
    final b = web.addresses.firstWhere((e) => e.ip == '10.42.0.7');
    expect(b.ready, isFalse);
    expect(b.nodeName, 'node02');
    expect(web.addresses.first.ready, isTrue, reason: 'ready rows first');
  });

  test('storage keeps access modes on claims and volumes', () {
    const raw = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "PersistentVolume",
      "metadata": {"name": "pvc-123"},
      "spec": {"capacity": {"storage": "10Gi"}, "accessModes": ["ReadWriteOnce"]},
      "status": {"phase": "Bound"}
    },
    {
      "kind": "PersistentVolumeClaim",
      "metadata": {"name": "pg", "namespace": "db"},
      "spec": {"accessModes": ["ReadWriteMany", "ReadOnlyMany"]},
      "status": {"phase": "Bound"}
    }
  ]
}
''';
    final storage = parseStorage(raw);
    expect(storage.volumes.single.accessModes, ['ReadWriteOnce']);
    expect(storage.volumes.single.accessModesLabel, 'RWO');
    expect(storage.claims.single.accessModesLabel, 'RWX, ROX');
  });

  test('pod spec names the PVCs it mounts (StatefulSet pod uses real claim)',
      () {
    const raw = r'''
{
  "kind": "List",
  "items": [
    {
      "kind": "StatefulSet",
      "metadata": {"name": "pg", "namespace": "db"},
      "spec": {"replicas": 1,
               "template": {"spec": {"containers": [{"name": "pg"}]}},
               "volumeClaimTemplates": [{"metadata": {"name": "data"}}]},
      "status": {"readyReplicas": 1}
    },
    {
      "kind": "Pod",
      "metadata": {"name": "pg-0", "namespace": "db",
                   "ownerReferences": [{"kind": "StatefulSet", "name": "pg"}]},
      "spec": {"containers": [{"name": "pg"}],
               "volumes": [
                 {"name": "data", "persistentVolumeClaim": {"claimName": "data-pg-0"}},
                 {"name": "cfg", "configMap": {"name": "pg-conf"}}
               ]},
      "status": {"phase": "Running"}
    }
  ]
}
''';
    final rows = parseWorkloadList(raw).rows;
    final sts = rows.firstWhere((r) => r.kind == K8sKind.statefulSet);
    final pod = rows.firstWhere((r) => r.kind == K8sKind.pod);
    expect(pod.config?.claims, ['data-pg-0']);
    expect(sts.config?.claims, isEmpty,
        reason: 'template has no claim; only the Pod names data-pg-0');
  });

  test('storage: PVC phase and PV phase drive health', () {
    final storage = parseStorage(_storage);
    expect(storage.claims, hasLength(2));
    expect(storage.volumes, hasLength(2));
    final pending = storage.claims.firstWhere((c) => c.name == 'data');
    expect(pending.health, HealthStatus.warning);
    expect(pending.requested, '5Gi');
    expect(storage.pendingClaims, 1);
    final released = storage.volumes.firstWhere((v) => v.name == 'old-nfs');
    expect(released.health, HealthStatus.warning);
    expect(released.claim, 'x/gone');
    expect(storage.unhealthyVolumes, 1);
    final bound = storage.volumes.firstWhere((v) => v.name == 'pvc-123');
    expect(bound.claim, 'db/pg');
    expect(bound.health, HealthStatus.healthy);
  });

  test('probes refuse to report empty when kubectl produced no JSON', () {
    expect(
      () => const ServiceListProbe().parse('', 'Error from server (Forbidden)', 1),
      throwsA(isA<K8sReadException>().having(
        (e) => e.toString(),
        'message',
        'Could not read services: Error from server (Forbidden)',
      )),
    );
    expect(
      () => const StorageListProbe().parse('---NO_KUBECTL---\n', '', 0),
      throwsA(isA<K8sReadException>()),
    );
    expect(
      const ClusterEventsProbe().parse('{"kind":"List","items":[]}', '', 0),
      isEmpty,
    );
  });

  test('probe commands are read-only cluster-wide gets', () {
    final facts = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);
    expect(const ClusterEventsProbe().command(facts),
        contains('get events -A --field-selector type=Warning -o json'));
    expect(const ServiceListProbe().command(facts),
        contains('get svc,endpoints -A -o json'));
    expect(const StorageListProbe().command(facts),
        contains('get pv,pvc -A -o json'));
    expect(const StorageListProbe().command(HostFacts.undiscovered),
        'echo ---NO_KUBECTL---');
  });

  test('k8sAge buckets', () {
    final now = DateTime.utc(2026, 11, 2, 12);
    expect(k8sAge(now.subtract(const Duration(seconds: 30)), now), '30s');
    expect(k8sAge(now.subtract(const Duration(minutes: 5)), now), '5m');
    expect(k8sAge(now.subtract(const Duration(hours: 3)), now), '3h');
    expect(k8sAge(now.subtract(const Duration(days: 4)), now), '4d');
    expect(k8sAge(null, now), '');
  });

  group('rollout history', () {
    test('deployment ReplicaSets: image change, restart, template change', () {
      final revs = parseRolloutHistory(_list([
        _rs(name: 'web-1', revision: 3, created: '2026-11-01T09:00:00Z', image: 'nginx:1.27'),
        _rs(name: 'web-2', revision: 4, created: '2026-11-02T09:00:00Z', image: 'nginx:1.27', restartedAt: '2026-11-02T09:00:00Z'),
        _rs(name: 'web-3', revision: 5, created: '2026-11-02T11:00:00Z', image: 'nginx:1.27', restartedAt: '2026-11-02T09:00:00Z', cause: 'raise memory'),
        _rs(name: 'web-0', revision: 2, created: '2026-10-30T09:00:00Z', image: 'nginx:1.25'),
      ]));
      expect(revs.map((r) => r.revision), [5, 4, 3, 2]);
      expect(revs.first.current, isTrue);
      expect(revs.skip(1).every((r) => !r.current), isTrue);
      expect(revs[0].changeLabel, 'template change');
      expect(revs[0].changeCause, 'raise memory');
      expect(revs[1].changeLabel, 'restart');
      expect(revs[2].changeLabel, 'web nginx:1.25 → nginx:1.27');
      expect(revs[3].changeLabel, 'oldest kept');
      expect(revs[0].ownerKind, K8sKind.deployment);
      expect(revs[0].ownerLabel, 'deploy shop/web');
    });

    test('revision 1 is created; added and removed containers are named', () {
      final revs = parseRolloutHistory(_list([
        _rs(name: 'a', revision: 1, created: '2026-11-01T09:00:00Z', image: 'nginx:1.25'),
        _rs(name: 'b', revision: 2, created: '2026-11-01T10:00:00Z', image: 'nginx:1.25', sidecar: 'fluentbit:3'),
        _rs(name: 'c', revision: 3, created: '2026-11-01T11:00:00Z', image: 'nginx:1.25'),
      ]));
      expect(revs.map((r) => r.changeLabel), [
        'removed log',
        'added log',
        'created',
      ]);
    });

    test('rollback is flagged from revision-history', () {
      final revs = parseRolloutHistory(_list([
        _rs(name: 'old', revision: 3, created: '2026-10-01T09:00:00Z', image: 'nginx:1.25', history: '1'),
        _rs(name: 'new', revision: 2, created: '2026-11-01T09:00:00Z', image: 'nginx:1.27'),
      ]));
      final rb = revs.firstWhere((r) => r.revision == 3);
      expect(rb.rollback, isTrue);
      expect(rb.current, isTrue);
      expect(rb.changeLabel, 'rollback · web nginx:1.27 → nginx:1.25');
      // The ReplicaSet is old; the rollback happened after revision 2 was
      // created, so it sorts as newest with a lower-bound age.
      expect(rb.createdAt, DateTime.utc(2026, 10, 1, 9));
      expect(rb.changedAt, DateTime.utc(2026, 11, 1, 9));
      expect(rb.changedAfter, isTrue);
      expect(revs.first.revision, 3);
      expect(rb.ageLabel(DateTime.utc(2026, 11, 1, 11)), '<2h');
      expect(revs.last.ageLabel(DateTime.utc(2026, 11, 1, 11)), '2h');
    });

    test('StatefulSet rollback is detected from creation order', () {
      const raw = r'''
{"kind": "List", "items": [
  {"kind": "ControllerRevision", "revision": 3,
   "metadata": {"name": "db-a", "namespace": "data", "creationTimestamp": "2026-10-01T10:00:00Z",
     "ownerReferences": [{"kind": "StatefulSet", "name": "db", "controller": true}]},
   "data": {"spec": {"template": {"spec": {"containers": [{"name": "pg", "image": "postgres:16.2"}]}}}}},
  {"kind": "ControllerRevision", "revision": 2,
   "metadata": {"name": "db-b", "namespace": "data", "creationTimestamp": "2026-11-02T10:00:00Z",
     "ownerReferences": [{"kind": "StatefulSet", "name": "db", "controller": true}]},
   "data": {"spec": {"template": {"spec": {"containers": [{"name": "pg", "image": "postgres:16.4"}]}}}}}
]}
''';
      final revs = parseRolloutHistory(raw);
      expect(revs.first.revision, 3);
      expect(revs.first.rollback, isTrue);
      expect(revs.first.changeLabel, 'rollback · pg postgres:16.4 → postgres:16.2');
      expect(revs.last.rollback, isFalse);
    });

    test('not capped: every kept revision is returned', () {
      final revs = parseRolloutHistory(_list([
        for (var i = 1; i <= 250; i++)
          _rs(
            name: 'rs-$i',
            revision: i,
            created: DateTime.utc(2026, 1, 1).add(Duration(hours: i)).toIso8601String(),
            image: 'img:$i',
          ),
      ]));
      expect(revs, hasLength(250));
    });

    test('StatefulSet ControllerRevisions; orphans skipped; init marked', () {
      final revs = parseRolloutHistory(_stsRevisions);
      expect(revs, hasLength(2));
      expect(revs.first.ownerKind, K8sKind.statefulSet);
      expect(revs.first.ownerLabel, 'sts data/db');
      expect(revs.first.changeLabel, 'pg postgres:16.2 → postgres:16.4');
      expect(revs.first.images.first.label, 'init-perm (init)');
      expect(revs.last.changeLabel, 'created');
    });

    test('ReplicaSet without a Deployment owner is skipped', () {
      final revs = parseRolloutHistory(_list([
        _rs(name: 'x', revision: 1, created: '2026-11-01T09:00:00Z', image: 'a', ownerKind: 'Job'),
      ]));
      expect(revs, isEmpty);
    });

    test('junk yields nothing; revisionsOf filters by owner', () {
      expect(parseRolloutHistory(''), isEmpty);
      expect(parseRolloutHistory('error: forbidden'), isEmpty);
      expect(
        parseRolloutHistory('{"items": [1, "x", {"kind": "ReplicaSet"}]}'),
        isEmpty,
      );
      final revs = parseRolloutHistory(_list([
        _rs(name: 'a', revision: 1, created: '2026-11-01T09:00:00Z', image: 'a'),
        _rs(name: 'b', revision: 2, created: '2026-11-01T10:00:00Z', image: 'b'),
        _rs(name: 'c', revision: 1, created: '2026-11-01T11:00:00Z', image: 'c', owner: 'api'),
      ]));
      const web = K8sWorkload(
        kind: K8sKind.deployment,
        namespace: 'shop',
        name: 'web',
        ready: 1,
        desired: 1,
      );
      expect(revisionsOf(revs, web).map((r) => r.revision), [2, 1]);
    });

    test('probe: cluster-wide or one namespace; no JSON is a read error', () {
      final facts =
          HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);
      expect(
        const RolloutHistoryProbe().command(facts),
        contains('get rs,controllerrevision -A -o json'),
      );
      expect(
        const RolloutHistoryProbe(namespace: 'shop').command(facts),
        contains("-n 'shop' -o json"),
      );
      expect(
        () => const RolloutHistoryProbe()
            .parse('', 'Error from server (Forbidden)', 1),
        throwsA(isA<K8sReadException>()),
      );
    });
  });
}
