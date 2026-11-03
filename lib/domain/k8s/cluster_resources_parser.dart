import 'dart:convert';

import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';

/// `get events -A --field-selector type=Warning -o json`, newest first.
List<K8sClusterEvent> parseClusterEvents(String stdout, {int limit = 100}) {
  final events = <K8sClusterEvent>[
    for (final item in _items(stdout))
      if (item['kind'] == 'Event' || item['kind'] == null) _event(item),
  ];
  events.sort((a, b) {
    final at = a.at;
    final bt = b.at;
    if (at == null && bt == null) {
      return 0;
    }
    if (at == null) {
      return 1;
    }
    if (bt == null) {
      return -1;
    }
    return bt.compareTo(at);
  });
  return events.take(limit).toList(growable: false);
}

K8sClusterEvent _event(Map<String, dynamic> raw) {
  final meta = _map(raw['metadata']);
  final obj = _map(raw['involvedObject']).isNotEmpty
      ? _map(raw['involvedObject'])
      : _map(raw['regarding']);
  final series = _map(raw['series']);
  final count = _int(raw['count']) ?? _int(series['count']) ?? 1;
  final at = _time(raw['lastTimestamp']) ??
      _time(series['lastObservedTime']) ??
      _time(raw['eventTime']) ??
      _time(raw['firstTimestamp']) ??
      _time(meta['creationTimestamp']);
  // Cluster-scoped objects (Node, PV) have no namespace; the Event's own
  // namespace (often default / kube-system) must not leak into the label.
  final namespace = obj.isNotEmpty
      ? obj['namespace'] as String? ?? ''
      : meta['namespace'] as String? ?? '';
  return K8sClusterEvent(
    namespace: namespace,
    type: raw['type'] as String? ?? '',
    reason: raw['reason'] as String? ?? '',
    message: (raw['message'] as String? ?? raw['note'] as String? ?? '').trim(),
    objectKind: obj['kind'] as String? ?? '',
    objectName: obj['name'] as String? ?? '',
    count: count,
    at: at,
  );
}

/// `get svc,endpoints -A -o json`: Services joined to their Endpoints.
K8sNetworking parseNetworking(String stdout) {
  final endpoints = <String, List<K8sEndpointAddress>>{};
  final services = <Map<String, dynamic>>[];
  for (final item in _items(stdout)) {
    switch (item['kind']) {
      case 'Service':
        services.add(item);
      case 'Endpoints':
        final meta = _map(item['metadata']);
        final key = '${meta['namespace'] ?? ''}/${meta['name'] ?? ''}';
        endpoints[key] = _endpointAddresses(item['subsets']);
    }
  }
  final rows = <K8sService>[];
  for (final raw in services) {
    final meta = _map(raw['metadata']);
    final ns = meta['namespace'] as String? ?? '';
    final name = meta['name'] as String? ?? '';
    if (name.isEmpty) {
      continue;
    }
    final spec = _map(raw['spec']);
    final type = spec['type'] as String? ?? 'ClusterIP';
    final selector = _map(spec['selector']);
    final ep = endpoints['$ns/$name'] ?? const <K8sEndpointAddress>[];
    rows.add(
      K8sService(
        namespace: ns,
        name: name,
        type: type,
        clusterIp: spec['clusterIP'] as String? ?? '',
        ports: _ports(spec['ports']),
        hasSelector: selector.isNotEmpty && type != 'ExternalName',
        readyEndpoints: ep.where((a) => a.ready).length,
        notReadyEndpoints: ep.where((a) => !a.ready).length,
        selector: {
          for (final e in selector.entries) e.key: '${e.value}',
        },
        portList: _portList(spec['ports']),
        addresses: ep,
        externalAddress: type == 'ExternalName'
            ? spec['externalName'] as String? ?? ''
            : _lbAddress(raw['status']),
      ),
    );
  }
  return K8sNetworking(services: rows);
}

/// One row per IP across subsets (multi-port Services repeat the IP). An
/// IP ready in any subset counts as ready. Ready rows first.
List<K8sEndpointAddress> _endpointAddresses(Object? subsets) {
  final ready = <String, K8sEndpointAddress>{};
  final notReady = <String, K8sEndpointAddress>{};
  if (subsets is List) {
    for (final s in subsets) {
      if (s is! Map) {
        continue;
      }
      _collectAddresses(s['addresses'], ready, ready: true);
      _collectAddresses(s['notReadyAddresses'], notReady, ready: false);
    }
  }
  notReady.removeWhere((ip, _) => ready.containsKey(ip));
  return [...ready.values, ...notReady.values];
}

void _collectAddresses(
  Object? list,
  Map<String, K8sEndpointAddress> into, {
  required bool ready,
}) {
  if (list is! List) {
    return;
  }
  for (final a in list) {
    if (a is! Map) {
      continue;
    }
    final ip = a['ip'] as String? ?? a['hostname'] as String? ?? '';
    if (ip.isEmpty || into.containsKey(ip)) {
      continue;
    }
    final ref = _map(a['targetRef']);
    into[ip] = K8sEndpointAddress(
      ip: ip,
      ready: ready,
      nodeName: a['nodeName'] as String? ?? '',
      targetKind: ref['kind'] as String? ?? '',
      targetNamespace: ref['namespace'] as String? ?? '',
      targetName: ref['name'] as String? ?? '',
    );
  }
}

List<K8sServicePort> _portList(Object? ports) {
  if (ports is! List) {
    return const [];
  }
  return [
    for (final p in ports)
      if (p is Map && _int(p['port']) != null)
        K8sServicePort(
          port: _int(p['port'])!,
          nodePort: _int(p['nodePort']),
          protocol: p['protocol'] as String? ?? 'TCP',
          targetPort: p['targetPort'] == null ? '' : '${p['targetPort']}',
        ),
  ];
}

List<String> _strings(Object? v) {
  if (v is! List) {
    return const [];
  }
  return [
    for (final s in v)
      if (s is String) s,
  ];
}

String _ports(Object? ports) {
  if (ports is! List) {
    return '';
  }
  return [
    for (final p in ports)
      if (p is Map)
        '${p['port']}${p['nodePort'] == null ? '' : ':${p['nodePort']}'}'
            '/${p['protocol'] ?? 'TCP'}',
  ].join(', ');
}

String _lbAddress(Object? status) {
  final ingress = _map(_map(status)['loadBalancer'])['ingress'];
  if (ingress is! List) {
    return '';
  }
  for (final i in ingress) {
    if (i is Map) {
      final v = i['ip'] as String? ?? i['hostname'] as String? ?? '';
      if (v.isNotEmpty) {
        return v;
      }
    }
  }
  return '';
}

/// `get pv,pvc -A -o json`.
K8sStorage parseStorage(String stdout) {
  final claims = <K8sVolumeClaim>[];
  final volumes = <K8sPersistentVolume>[];
  for (final item in _items(stdout)) {
    final meta = _map(item['metadata']);
    final name = meta['name'] as String? ?? '';
    if (name.isEmpty) {
      continue;
    }
    final spec = _map(item['spec']);
    final status = _map(item['status']);
    switch (item['kind']) {
      case 'PersistentVolumeClaim':
        claims.add(
          K8sVolumeClaim(
            namespace: meta['namespace'] as String? ?? '',
            name: name,
            phase: status['phase'] as String? ?? '',
            capacity: _map(status['capacity'])['storage'] as String? ?? '',
            requested: _map(_map(spec['resources'])['requests'])['storage']
                    as String? ??
                '',
            storageClass: spec['storageClassName'] as String? ?? '',
            volumeName: spec['volumeName'] as String? ?? '',
            accessModes: _strings(spec['accessModes']),
          ),
        );
      case 'PersistentVolume':
        final ref = _map(spec['claimRef']);
        final claimName = ref['name'] as String? ?? '';
        volumes.add(
          K8sPersistentVolume(
            name: name,
            phase: status['phase'] as String? ?? '',
            capacity: _map(spec['capacity'])['storage'] as String? ?? '',
            claim: claimName.isEmpty
                ? ''
                : '${ref['namespace'] ?? ''}/$claimName',
            reclaimPolicy:
                spec['persistentVolumeReclaimPolicy'] as String? ?? '',
            storageClass: spec['storageClassName'] as String? ?? '',
            accessModes: _strings(spec['accessModes']),
          ),
        );
    }
  }
  return K8sStorage(claims: claims, volumes: volumes);
}

/// `get rs,controllerrevision -A -o json`: every kept revision of
/// Deployments, StatefulSets and DaemonSets, each compared with the previous
/// kept revision of its owner. Newest change first. Not capped: counts and
/// per-workload lookups need the whole set; lists cap at display time.
List<K8sRevision> parseRolloutHistory(String stdout) {
  final byOwner = <String, List<K8sRevision>>{};
  for (final item in _items(stdout)) {
    final rev = _revision(item);
    if (rev == null) {
      continue;
    }
    final key = '${rev.ownerKind.name}|${rev.namespace}|${rev.ownerName}';
    byOwner.putIfAbsent(key, () => []).add(rev);
  }
  final out = <K8sRevision>[];
  for (final revs in byOwner.values) {
    revs.sort((a, b) => a.revision.compareTo(b.revision));
    DateTime? newestBefore;
    for (var i = 0; i < revs.length; i++) {
      final cur = revs[i];
      final created = cur.createdAt;
      // A revision created before an older-numbered one is a reused
      // template: `rollout undo` renumbers it instead of creating a new
      // object. Deployments also mark it with revision-history; StatefulSets
      // and DaemonSets only show it this way.
      final reused = created != null &&
          newestBefore != null &&
          created.isBefore(newestBefore);
      final rollback = cur.rollback || reused;
      out.add(
        K8sRevision(
          ownerKind: cur.ownerKind,
          namespace: cur.namespace,
          ownerName: cur.ownerName,
          revision: cur.revision,
          createdAt: created,
          images: cur.images,
          restartedAt: cur.restartedAt,
          changeCause: cur.changeCause,
          rollback: rollback,
          changes: _revisionChanges(
            i == 0 ? null : revs[i - 1],
            cur,
            rollback: rollback,
          ),
          current: i == revs.length - 1,
          changedAt: reused ? newestBefore : created,
          changedAfter: reused,
        ),
      );
      if (created != null &&
          (newestBefore == null || created.isAfter(newestBefore))) {
        newestBefore = created;
      }
    }
  }
  out.sort((a, b) {
    final at = a.changedAt;
    final bt = b.changedAt;
    if (at != null && bt != null && at != bt) {
      return bt.compareTo(at);
    }
    if (at == null && bt != null) {
      return 1;
    }
    if (bt == null && at != null) {
      return -1;
    }
    return b.revision.compareTo(a.revision);
  });
  return out;
}

/// Raw revision without [K8sRevision.changes] / [K8sRevision.current].
/// Null for orphans, foreign owners, or rows with no revision number.
K8sRevision? _revision(Map<String, dynamic> item) {
  final meta = _map(item['metadata']);
  final owner = _controllerOwner(meta['ownerReferences']);
  if (owner == null) {
    return null;
  }
  final annotations = _map(meta['annotations']);
  final Map<String, dynamic> template;
  final int? revision;
  switch (item['kind']) {
    case 'ReplicaSet':
      if (owner.kind != K8sKind.deployment) {
        return null;
      }
      revision = int.tryParse(
        '${annotations['deployment.kubernetes.io/revision'] ?? ''}',
      );
      template = _map(_map(item['spec'])['template']);
    case 'ControllerRevision':
      if (owner.kind != K8sKind.statefulSet &&
          owner.kind != K8sKind.daemonSet) {
        return null;
      }
      revision = _int(item['revision']);
      template = _map(_map(_map(item['data'])['spec'])['template']);
    default:
      return null;
  }
  if (revision == null) {
    return null;
  }
  final podSpec = _map(template['spec']);
  final templateAnnotations = _map(_map(template['metadata'])['annotations']);
  final history =
      '${annotations['deployment.kubernetes.io/revision-history'] ?? ''}';
  return K8sRevision(
    ownerKind: owner.kind,
    namespace: _str(meta['namespace']),
    ownerName: owner.name,
    revision: revision,
    createdAt: _time(meta['creationTimestamp']),
    images: [
      ..._images(podSpec['initContainers'], init: true),
      ..._images(podSpec['containers'], init: false),
    ],
    restartedAt:
        '${templateAnnotations['kubectl.kubernetes.io/restartedAt'] ?? ''}',
    changeCause: '${annotations['kubernetes.io/change-cause'] ?? ''}'.trim(),
    rollback: history.trim().isNotEmpty,
  );
}

({K8sKind kind, String name})? _controllerOwner(Object? refs) {
  if (refs is! List) {
    return null;
  }
  for (final r in refs) {
    if (r is! Map || r['controller'] != true) {
      continue;
    }
    final kind = parseK8sKind(_str(r['kind']));
    final name = _str(r['name']);
    if (kind == null || name.isEmpty) {
      return null;
    }
    return (kind: kind, name: name);
  }
  return null;
}

List<K8sRevisionImage> _images(Object? containers, {required bool init}) {
  if (containers is! List) {
    return const [];
  }
  return [
    for (final c in containers)
      if (c is Map && _str(c['name']).isNotEmpty)
        K8sRevisionImage(
          name: _str(c['name']),
          image: _str(c['image']),
          init: init,
        ),
  ];
}

List<String> _revisionChanges(
  K8sRevision? prev,
  K8sRevision cur, {
  required bool rollback,
}) {
  final out = <String>[if (rollback) 'rollback'];
  if (prev == null) {
    out.add(cur.revision == 1 ? 'created' : 'oldest kept');
    return out;
  }
  String key(K8sRevisionImage i) => '${i.init}|${i.name}';
  final before = {for (final i in prev.images) key(i): i};
  final after = {for (final i in cur.images) key(i): i};
  final imageChanges = <String>[];
  for (final e in after.entries) {
    final old = before[e.key];
    if (old == null) {
      imageChanges.add('added ${e.value.label}');
    } else if (old.image != e.value.image) {
      imageChanges.add('${e.value.label} ${old.image} → ${e.value.image}');
    }
  }
  for (final e in before.entries) {
    if (!after.containsKey(e.key)) {
      imageChanges.add('removed ${e.value.label}');
    }
  }
  if (imageChanges.isNotEmpty) {
    out.addAll(imageChanges);
  } else if (cur.restartedAt != prev.restartedAt) {
    out.add('restart');
  } else if (!rollback) {
    out.add('template change');
  }
  return out;
}

/// String field or empty; junk types never throw.
String _str(Object? v) => v is String ? v : '';

List<Map<String, dynamic>> _items(String stdout) {
  final decoded = _jsonMap(stdout);
  if (decoded == null) {
    return const [];
  }
  final items = decoded['items'];
  if (items is! List) {
    return const [];
  }
  return [
    for (final item in items)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

DateTime? _time(Object? v) {
  if (v is! String || v.isEmpty) {
    return null;
  }
  return DateTime.tryParse(v);
}

int? _int(Object? v) {
  if (v is int) {
    return v;
  }
  if (v is num) {
    return v.toInt();
  }
  return null;
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return const {};
}

Map<String, dynamic>? _jsonMap(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw.substring(start));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } on FormatException {
    return null;
  }
  return null;
}
