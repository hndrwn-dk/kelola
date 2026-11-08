import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/data/db/database.dart';
import 'package:kelola/data/db/host_repository.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/presentation/fleet/fleet_k8s_read.dart';
import 'package:sqlite3/sqlite3.dart';

const _nodes = '''
---HOSTNAME---
cp1
---READYZ---
ok
---NODES---
{"items": [
  {"metadata": {"name": "cp1", "labels": {"node-role.kubernetes.io/control-plane": ""}},
   "status": {"conditions": [{"type": "Ready", "status": "True"}]}},
  {"metadata": {"name": "w1"},
   "status": {"conditions": [{"type": "Ready", "status": "False"}]}}
]}
''';

const _noJson = '''
---HOSTNAME---
cp1
---READYZ---
---READYZ_FAIL---
---NODES---
''';

FleetHostHealth _host({FleetK8sSummary? k8s, bool reachable = true}) {
  return FleetHostHealth(
    hostId: 'h1',
    alias: 'k3s-lab',
    reachable: reachable,
    load1: 0.1,
    nprocCores: 4,
    failedUnitCount: 0,
    pendingUpdates: 0,
    fetchedAt: DateTime.utc(2026, 11, 3),
    k8s: k8s,
  );
}

const _inv = WorkloadInventory(
  rows: [
    K8sWorkload(
      kind: K8sKind.deployment,
      namespace: 'shop',
      name: 'api',
      ready: 0,
      desired: 1,
      health: HealthStatus.failed,
    ),
    K8sWorkload(
      kind: K8sKind.deployment,
      namespace: 'shop',
      name: 'web',
      ready: 1,
      desired: 2,
      health: HealthStatus.warning,
    ),
    K8sWorkload(
      kind: K8sKind.deployment,
      namespace: 'shop',
      name: 'ok',
      ready: 1,
      desired: 1,
      health: HealthStatus.healthy,
    ),
  ],
);

void main() {
  group('summary', () {
    test('from cluster + workloads; label; encode round-trip', () {
      final read = const FleetClusterProbe().parse(_nodes, '', 0);
      expect(read.nodesRead, isTrue);
      final s = fleetK8sSummary(read, _inv);
      expect(s.read, isTrue);
      expect(s.apiReachable, isTrue);
      expect(s.nodesReady, 1);
      expect(s.nodesTotal, 2);
      expect(s.failedWorkloads, 1);
      expect(s.warningWorkloads, 1);
      expect(s.down, isTrue);
      expect(s.label, '1/2 nodes · 1 failed · 1 warn');

      final back = FleetK8sSummary.decode(s.encode())!;
      expect(back.label, s.label);
      expect(back.read, isTrue);
    });

    test('no node JSON: refused connection is API down, else unreadable', () {
      final denied = const FleetClusterProbe()
          .parse(_noJson, 'Error from server (Forbidden): nodes is forbidden', 1);
      expect(fleetK8sSummary(denied, _inv).read, isFalse);
      expect(fleetK8sSummary(denied, _inv).label, 'not readable');

      final sudo = const FleetClusterProbe()
          .parse(_noJson, 'sudo: a password is required', 1);
      expect(fleetK8sSummary(sudo, _inv).read, isFalse);

      final refused = const FleetClusterProbe().parse(
        _noJson,
        'The connection to the server 127.0.0.1:6443 was refused - '
            'did you specify the right host or port?\n'
            'Unable to connect to the server: dial tcp 127.0.0.1:6443: '
            'connect: connection refused',
        1,
      );
      final down = fleetK8sSummary(refused, _inv);
      expect(down.read, isTrue);
      expect(down.apiReachable, isFalse);
      expect(down.down, isTrue);
      expect(down.label, 'API down');
    });

    test('no-kubeconfig localhost:8080 refusal is not API down', () {
      final noConfig = const FleetClusterProbe().parse(
        _noJson,
        'The connection to the server localhost:8080 was refused - '
            'did you specify the right host or port?',
        1,
      );
      expect(noConfig.connectionRefused, isFalse);
      expect(fleetK8sSummary(noConfig, _inv).read, isFalse);
    });

    test('failed workload list keeps the previous workload counts', () {
      final read = const FleetClusterProbe().parse(_nodes, '', 0);
      const previous = FleetK8sSummary(
        read: true,
        apiReachable: true,
        nodesReady: 2,
        nodesTotal: 2,
        failedWorkloads: 3,
        warningWorkloads: 1,
      );
      final s = fleetK8sSummary(read, null, previous: previous);
      expect(s.read, isTrue);
      expect(s.nodesReady, 1);
      expect(s.failedWorkloads, 3);
      expect(s.warningWorkloads, 1);
      expect(fleetK8sSummary(read, null).failedWorkloads, 0);
    });

    test('decode tolerates empty and junk', () {
      expect(FleetK8sSummary.decode(''), isNull);
      expect(FleetK8sSummary.decode('nope'), isNull);
      expect(FleetK8sSummary.decode('[1]'), isNull);
      expect(FleetK8sSummary.decode('{"read": "x"}')!.read, isFalse);
    });
  });

  group('assessment', () {
    test('k8s issues: down is failed, failed workloads are a warning', () {
      final down = assessFleetHost(
        _host(
          k8s: const FleetK8sSummary(read: true, nodesReady: 1, nodesTotal: 1),
        ),
      );
      expect(down.issues.single.kind, FleetIssueKind.k8sDown);
      expect(down.issues.single.meta, 'k8s API down');
      expect(down.tileHealth, FleetTileHealth.failed);

      final failing = assessFleetHost(
        _host(
          k8s: const FleetK8sSummary(
            read: true,
            apiReachable: true,
            nodesReady: 2,
            nodesTotal: 2,
            failedWorkloads: 3,
          ),
        ),
      );
      expect(failing.issues.single.kind, FleetIssueKind.k8sWorkloads);
      expect(failing.issues.single.meta, 'k8s 3 failed workloads');
      expect(failing.tileHealth, FleetTileHealth.warning);
    });

    test('unreadable, warnings only, or no kubectl raise nothing', () {
      for (final k8s in [
        FleetK8sSummary.unreadable,
        const FleetK8sSummary(
          read: true,
          apiReachable: true,
          nodesReady: 1,
          nodesTotal: 1,
          warningWorkloads: 4,
        ),
        null,
      ]) {
        expect(assessFleetHost(_host(k8s: k8s)).issues, isEmpty);
      }
    });

    test('tile shows a short k8s cell only when there is trouble', () {
      bool hasCell(FleetHostHealth h) =>
          h.tileMetrics().any((m) => m.label == 'k8s');
      String cell(FleetHostHealth h) =>
          h.tileMetrics().firstWhere((m) => m.label == 'k8s').value;
      expect(hasCell(_host()), isFalse);
      expect(hasCell(_host(k8s: FleetK8sSummary.unreadable)), isFalse);
      expect(
        hasCell(
          _host(
            k8s: const FleetK8sSummary(
              read: true,
              apiReachable: true,
              nodesReady: 3,
              nodesTotal: 3,
              warningWorkloads: 2,
            ),
          ),
        ),
        isFalse,
      );
      expect(cell(_host(k8s: FleetK8sSummary.apiDown)), 'down');
      expect(
        cell(
          _host(
            k8s: const FleetK8sSummary(
              read: true,
              apiReachable: true,
              nodesReady: 3,
              nodesTotal: 3,
              failedWorkloads: 2,
            ),
          ),
        ),
        '2 fail',
      );
    });
  });

  group('read', () {
    final kubectl = HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']);

    test('no kubectl: null and no probe runs', () async {
      var calls = 0;
      final s = await readFleetK8s(
        HostFacts.undiscovered,
        <T>(Probe<T> p) async {
          calls++;
          throw StateError('no');
        },
      );
      expect(s, isNull);
      expect(calls, 0);
    });

    test('cluster read throws: unreadable, not unreachable', () async {
      final s = await readFleetK8s(
        kubectl,
        <T>(Probe<T> p) async => throw StateError('ssh hiccup'),
      );
      expect(s!.read, isFalse);
    });

    test('workload list with no JSON keeps the previous counts', () async {
      expect(
        () => const FleetWorkloadListProbe()
            .parse('', 'error: the server doesn\'t have a resource type', 1),
        throwsA(isA<K8sReadException>()),
      );
      expect(
        const FleetWorkloadListProbe()
            .parse('{"items": []}', '', 0)
            .rows,
        isEmpty,
      );
      const previous = FleetK8sSummary(
        read: true,
        apiReachable: true,
        nodesReady: 2,
        nodesTotal: 2,
        failedWorkloads: 2,
      );
      final s = await readFleetK8s(
        kubectl,
        <T>(Probe<T> p) async {
          if (p is FleetClusterProbe) {
            return p.parse(_nodes, '', 0) as T;
          }
          // kubectl printed its error and no JSON.
          return p.parse('', 'Unable to list pods', 1);
        },
        previous: previous,
      );
      expect(s!.failedWorkloads, 2);
    });

    test('workload list failing keeps the node verdict', () async {
      final probes = <Probe<dynamic>>[];
      final s = await readFleetK8s(kubectl, <T>(Probe<T> p) async {
        probes.add(p);
        if (p is FleetClusterProbe) {
          return p.parse(_nodes, '', 0) as T;
        }
        throw StateError('list failed');
      });
      expect(probes.map((p) => p.runtimeType), [
        FleetClusterProbe,
        FleetWorkloadListProbe,
      ]);
      expect(s!.read, isTrue);
      expect(s.nodesTotal, 2);
      expect(s.failedWorkloads, 0);
    });
  });

  group('cache', () {
    test('fleet cache round-trips the k8s summary', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final host = await repo.insert(
        alias: 'k3s-lab',
        address: '10.0.0.5',
        port: 22,
        username: 'ops',
      );
      final plain = await repo.insert(
        alias: 'plain',
        address: '10.0.0.6',
        port: 22,
        username: 'ops',
      );
      const k8s = FleetK8sSummary(
        read: true,
        apiReachable: true,
        nodesReady: 3,
        nodesTotal: 3,
        failedWorkloads: 1,
      );
      await repo.saveFleetCache(
        FleetHostHealth(
          hostId: host.id,
          alias: host.alias,
          reachable: true,
          load1: 0,
          failedUnitCount: 0,
          pendingUpdates: 0,
          fetchedAt: DateTime.utc(2026, 11, 3),
          k8s: k8s,
        ),
      );
      await repo.saveFleetCache(
        FleetHostHealth(
          hostId: plain.id,
          alias: plain.alias,
          reachable: true,
          load1: 0,
          failedUnitCount: 0,
          pendingUpdates: 0,
          fetchedAt: DateTime.utc(2026, 11, 3),
        ),
      );
      final cache = await repo.loadFleetCacheByHost();
      expect(cache[host.id]!.k8s!.label, '3/3 nodes · 1 failed');
      expect(cache[plain.id]!.k8s, isNull);
    });

    test('cached facts keep runtimes, so fleet can see kubectl', () async {
      final db = KelolaDatabase.memory();
      addTearDown(db.close);
      final repo = HostRepository(db);
      final host = await repo.insert(
        alias: 'k3s-lab',
        address: '10.0.0.5',
        port: 22,
        username: 'ops',
      );
      await repo.saveFacts(
        host.id,
        HostFacts.undiscovered.copyWith(runtimes: const ['docker', 'k3s']),
      );
      final facts = await repo.facts(host.id);
      expect(facts!.runtimes, ['docker', 'k3s']);
    });

    test('schema 25 adds fleet_cache.k8s_json', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('''
CREATE TABLE fleet_cache (
  host_id TEXT NOT NULL PRIMARY KEY,
  reachable INTEGER NOT NULL,
  load1 REAL NOT NULL,
  disk_root_percent INTEGER NOT NULL,
  failed_unit_count INTEGER NOT NULL,
  pending_updates INTEGER NOT NULL,
  fetched_at INTEGER NOT NULL
);
''');
      raw.execute('PRAGMA user_version = 24');
      final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final cols = await db.customSelect('PRAGMA table_info(fleet_cache)').get();
      expect(
        cols.map((r) => r.read<String>('name')).contains('k8s_json'),
        isTrue,
      );
    });

    test('schema 25 adds cached_facts.runtimes', () async {
      final raw = sqlite3.openInMemory();
      raw.execute('''
CREATE TABLE cached_facts (
  host_id TEXT NOT NULL PRIMARY KEY,
  os_id TEXT NOT NULL,
  os_version_id TEXT NOT NULL,
  pretty_name TEXT,
  init_system TEXT NOT NULL,
  systemd_version INTEGER,
  pkg TEXT NOT NULL,
  fw TEXT NOT NULL,
  has_journald INTEGER NOT NULL,
  journal_readable INTEGER NOT NULL,
  journal_access TEXT NOT NULL DEFAULT 'unknown',
  arch TEXT NOT NULL,
  discovered_at INTEGER NOT NULL
);
''');
      raw.execute('PRAGMA user_version = 24');
      final db = KelolaDatabase.connect(NativeDatabase.opened(raw));
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      final cols =
          await db.customSelect('PRAGMA table_info(cached_facts)').get();
      expect(
        cols.map((r) => r.read<String>('name')).contains('runtimes'),
        isTrue,
      );
    });
  });

  test('ClusterHealth is unaffected by the fleet wrapper', () {
    final read = const FleetClusterProbe().parse(_nodes, '', 0);
    expect(read.health, isA<ClusterHealth>());
    expect(read.health.apiReachable, isTrue);
  });
}
