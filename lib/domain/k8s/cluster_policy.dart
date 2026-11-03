import 'dart:convert';

import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/k8s/workload_config.dart';

/// Wave 3: configuration + security read models and findings.
///
/// ConfigMap / Secret inventory is metadata only: namespace, name, type and
/// key names, printed by a kubectl go-template on the host. Secret values
/// never cross SSH.

class K8sSecretMeta {
  const K8sSecretMeta({
    required this.namespace,
    required this.name,
    required this.type,
    required this.keys,
  });

  final String namespace;
  final String name;
  final String type;
  final List<String> keys;
}

class K8sConfigInventory {
  const K8sConfigInventory({
    this.configMaps = const {},
    this.secrets = const [],
    this.configMapsReadable = true,
    this.secretsReadable = true,
  });

  /// namespace → ConfigMap names.
  final Map<String, Set<String>> configMaps;
  final List<K8sSecretMeta> secrets;

  /// Secrets are often RBAC-restricted while ConfigMaps are not. A section
  /// that could not be read skips its missing-ref checks instead of
  /// reporting every reference as missing.
  final bool configMapsReadable;
  final bool secretsReadable;

  int get configMapCount =>
      configMaps.values.fold(0, (sum, names) => sum + names.length);

  bool hasConfigMap(String ns, String name) =>
      configMaps[ns]?.contains(name) ?? false;

  bool hasSecret(String ns, String name) =>
      secrets.any((s) => s.namespace == ns && s.name == name);
}

/// Output of [ConfigInventoryProbe]: `---CM---` / `---SECRET---` sections of
/// `ns|name|key1,key2,|…` lines, each section ending in `---*_FAIL---` when
/// kubectl failed.
K8sConfigInventory parseConfigInventory(String stdout) {
  final cmRaw = _section(stdout, 'CM') ?? '';
  final secretRaw = _section(stdout, 'SECRET') ?? '';
  final cmOk = stdout.contains('---CM---') && !cmRaw.contains('---CM_FAIL---');
  final secretOk = stdout.contains('---SECRET---') &&
      !secretRaw.contains('---SECRET_FAIL---');

  final configMaps = <String, Set<String>>{};
  if (cmOk) {
    for (final line in _lines(cmRaw)) {
      final parts = line.split('|');
      if (parts.length < 2 || parts[1].isEmpty) {
        continue;
      }
      configMaps.putIfAbsent(parts[0], () => <String>{}).add(parts[1]);
    }
  }
  final secrets = <K8sSecretMeta>[];
  if (secretOk) {
    for (final line in _lines(secretRaw)) {
      final parts = line.split('|');
      if (parts.length < 3 || parts[1].isEmpty) {
        continue;
      }
      secrets.add(K8sSecretMeta(
        namespace: parts[0],
        name: parts[1],
        type: parts[2],
        keys: parts.length > 3
            ? parts[3].split(',').where((k) => k.isNotEmpty).toList()
            : const [],
      ));
    }
  }
  return K8sConfigInventory(
    configMaps: configMaps,
    secrets: secrets,
    configMapsReadable: cmOk,
    secretsReadable: secretOk,
  );
}

class K8sSecurityInventory {
  const K8sSecurityInventory({
    this.serviceAccounts = 0,
    this.networkPolicyNamespaces = const {},
    this.clusterAdminGrants = const [],
  });

  final int serviceAccounts;

  /// Namespaces that have at least one NetworkPolicy.
  final Set<String> networkPolicyNamespaces;

  /// `binding: Kind subject` for cluster-admin granted to non-system
  /// subjects.
  final List<({String binding, String subject})> clusterAdminGrants;
}

/// `get sa,networkpolicy,clusterrolebinding -A -o json`.
K8sSecurityInventory parseSecurityInventory(String stdout) {
  var sas = 0;
  final netpol = <String>{};
  final grants = <({String binding, String subject})>[];
  for (final item in _items(stdout)) {
    final meta = _map(item['metadata']);
    switch (item['kind']) {
      case 'ServiceAccount':
        sas++;
      case 'NetworkPolicy':
        final ns = meta['namespace'] as String? ?? '';
        if (ns.isNotEmpty) {
          netpol.add(ns);
        }
      case 'ClusterRoleBinding':
        final role = _map(item['roleRef']);
        if (role['name'] != 'cluster-admin') {
          continue;
        }
        final binding = meta['name'] as String? ?? '';
        final subjects = item['subjects'];
        if (subjects is! List) {
          continue;
        }
        for (final s in subjects) {
          if (s is! Map) {
            continue;
          }
          final kind = s['kind'] as String? ?? '';
          final name = s['name'] as String? ?? '';
          if (_systemSubject(kind, name)) {
            continue;
          }
          final ns = s['namespace'] as String? ?? '';
          grants.add((
            binding: binding,
            subject: ns.isEmpty ? '$kind $name' : '$kind $ns/$name',
          ));
        }
    }
  }
  return K8sSecurityInventory(
    serviceAccounts: sas,
    networkPolicyNamespaces: netpol,
    clusterAdminGrants: grants,
  );
}

bool _systemSubject(String kind, String name) {
  if (name.startsWith('system:')) {
    return true;
  }
  // kubeadm's own admin group; k3s ships the same binding.
  return kind == 'Group' && name == 'kubeadm:cluster-admins';
}

/// One row on the Configuration / Security sections.
class K8sFinding {
  const K8sFinding({
    required this.subject,
    required this.issues,
    required this.health,
    this.workload,
  });

  /// `deploy shop/api`, `namespace shop`, `ClusterRoleBinding ops-admin`.
  final String subject;
  final List<String> issues;
  final HealthStatus health;

  /// Set when the finding is about a workload, so the row can open it.
  final K8sWorkload? workload;
}

/// Namespaces whose hygiene (requests/limits/probes/:latest) is not judged:
/// cluster add-ons the operator does not own.
bool isSystemNamespace(String ns) => ns.startsWith('kube-');

/// The Configuration section's hygiene rules for one container, so the
/// workload screen colours a container the same way the finding judges it.
/// Init containers and `kube-*` add-ons are not judged.
bool containerHygieneOk(K8sWorkload row, K8sContainerConfig c) {
  if (c.init || isSystemNamespace(row.namespace)) {
    return true;
  }
  final longRunning = row.kind != K8sKind.job && row.kind != K8sKind.cronJob;
  return c.hasRequests &&
      c.hasMemoryLimit &&
      (c.readinessProbe || !longRunning) &&
      !_floatingTag(c.image);
}

/// Missing ConfigMap/Secret refs (failed) and resource / probe / image
/// hygiene (warning), one finding per workload. Pods owned by a controller
/// are skipped; their owner carries the same template.
List<K8sFinding> configFindings(
  List<K8sWorkload> rows,
  K8sConfigInventory? inventory,
) {
  final out = <K8sFinding>[];
  for (final row in rows) {
    final config = row.config;
    if (config == null || config.ownedByController) {
      continue;
    }
    final missing = <String>[];
    final hygiene = <String>[];
    if (inventory != null) {
      for (final ref in config.refs) {
        if (ref.optional) {
          continue;
        }
        final isCm = ref.kind == 'ConfigMap';
        final readable =
            isCm ? inventory.configMapsReadable : inventory.secretsReadable;
        if (!readable) {
          continue;
        }
        final present = isCm
            ? inventory.hasConfigMap(row.namespace, ref.name)
            : inventory.hasSecret(row.namespace, ref.name);
        if (!present) {
          missing.add('missing ${ref.kind} ${ref.name}');
        }
      }
    }
    if (!isSystemNamespace(row.namespace)) {
      final apps = config.appContainers.toList();
      final noLimit = [for (final c in apps) if (!c.hasMemoryLimit) c.name];
      final noRequests = [for (final c in apps) if (!c.hasRequests) c.name];
      final longRunning =
          row.kind != K8sKind.job && row.kind != K8sKind.cronJob;
      final noReadiness = longRunning
          ? [for (final c in apps) if (!c.readinessProbe) c.name]
          : const <String>[];
      final latest = [
        for (final c in config.containers)
          if (_floatingTag(c.image)) c.name,
      ];
      if (noRequests.isNotEmpty) {
        hygiene.add('no requests: ${noRequests.join(', ')}');
      }
      if (noLimit.isNotEmpty) {
        hygiene.add('no memory limit: ${noLimit.join(', ')}');
      }
      if (noReadiness.isNotEmpty) {
        hygiene.add('no readiness probe: ${noReadiness.join(', ')}');
      }
      if (latest.isNotEmpty) {
        hygiene.add(':latest image: ${latest.join(', ')}');
      }
    }
    if (missing.isEmpty && hygiene.isEmpty) {
      continue;
    }
    out.add(K8sFinding(
      subject: '${row.kind.short} ${row.title}',
      issues: [...missing, ...hygiene],
      health: missing.isNotEmpty ? HealthStatus.failed : HealthStatus.warning,
      workload: row,
    ));
  }
  out.sort(_findingOrder);
  return out;
}

/// Image with no tag, or tag `latest`, and no digest pin.
bool _floatingTag(String image) {
  if (image.isEmpty || image.contains('@')) {
    return false;
  }
  final lastSegment = image.split('/').last;
  final colon = lastSegment.lastIndexOf(':');
  if (colon < 0) {
    return true;
  }
  return lastSegment.substring(colon + 1) == 'latest';
}

/// Privileged / host-namespace workloads, namespaces with workloads and no
/// NetworkPolicy, and cluster-admin granted to non-system subjects.
List<K8sFinding> securityFindings(
  List<K8sWorkload> rows,
  K8sSecurityInventory? inventory,
) {
  final out = <K8sFinding>[];
  final workloadNamespaces = <String>{};
  for (final row in rows) {
    final config = row.config;
    if (config == null || config.ownedByController) {
      continue;
    }
    workloadNamespaces.add(row.namespace);
    final issues = <String>[
      for (final c in config.containers)
        if (c.privileged) 'privileged: ${c.name}',
      if (config.hostNetwork) 'hostNetwork',
      if (config.hostPid) 'hostPID',
      if (config.hostIpc) 'hostIPC',
    ];
    if (issues.isEmpty) {
      continue;
    }
    out.add(K8sFinding(
      subject: '${row.kind.short} ${row.title}',
      issues: issues,
      // CNI / storage add-ons legitimately need these; flag, don't fail.
      health: HealthStatus.warning,
      workload: row,
    ));
  }
  if (inventory != null) {
    final open = workloadNamespaces
        .where((ns) =>
            !isSystemNamespace(ns) &&
            !inventory.networkPolicyNamespaces.contains(ns))
        .toList()
      ..sort();
    for (final ns in open) {
      out.add(K8sFinding(
        subject: 'namespace $ns',
        issues: const ['no NetworkPolicy: all pod traffic allowed'],
        health: HealthStatus.warning,
      ));
    }
    for (final g in inventory.clusterAdminGrants) {
      out.add(K8sFinding(
        subject: 'ClusterRoleBinding ${g.binding}',
        issues: ['cluster-admin → ${g.subject}'],
        health: HealthStatus.warning,
      ));
    }
  }
  out.sort(_findingOrder);
  return out;
}

int _findingOrder(K8sFinding a, K8sFinding b) {
  final h = worstHealthFirst(a.health, b.health);
  return h != 0 ? h : a.subject.compareTo(b.subject);
}

Iterable<String> _lines(String raw) =>
    raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

String? _section(String stdout, String name) {
  final startTag = '---$name---';
  final start = stdout.indexOf(startTag);
  if (start < 0) {
    return null;
  }
  final from = start + startTag.length;
  final rest = stdout.substring(from);
  final next = RegExp(r'\n---[A-Z]+---').firstMatch(rest);
  return next == null ? rest : rest.substring(0, next.start);
}

List<Map<String, dynamic>> _items(String stdout) {
  final start = stdout.indexOf('{');
  if (start < 0) {
    return const [];
  }
  try {
    final decoded = jsonDecode(stdout.substring(start));
    final items = decoded is Map ? decoded['items'] : null;
    if (items is! List) {
      return const [];
    }
    return [
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  } on FormatException {
    return const [];
  }
}

Map<String, dynamic> _map(Object? v) {
  if (v is Map) {
    return Map<String, dynamic>.from(v);
  }
  return const {};
}
