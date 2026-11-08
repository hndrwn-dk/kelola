import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_components.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_health.dart';
import 'package:kelola/domain/fleet/fleet_k8s.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';
import 'package:kelola/domain/k8s/cluster_resources.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/k8s/workload.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/presentation/fleet/fleet_k8s_read.dart';

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

final _oc = HostFacts.undiscovered.copyWith(runtimes: const ['oc']);

String _clusterOut({required bool openShift}) => [
      '---HOSTNAME---',
      'bastion',
      '---READYZ---',
      'ok',
      '---NODES---',
      _fixture('synthetic_nodes.json'),
      '---OPENSHIFT---',
      openShift
          ? _fixture('synthetic_config_openshift_io_v1.json')
          : '---OPENSHIFT_NONE---',
      '---AUTH---',
    ].join('\n');

String _ocpOut() => [
      '---CLUSTERVERSION---',
      _fixture('synthetic_clusterversion_healthy.json'),
      '---CLUSTEROPERATORS---',
      _fixture('synthetic_clusteroperators.json'),
      '---MCP---',
      '{"items":[]}',
      '---CSR---',
      '{"items":[]}',
    ].join('\n');

FleetHostHealth _host(FleetK8sSummary? k8s) => FleetHostHealth(
      hostId: 'h1',
      alias: 'crc-bastion',
      reachable: true,
      load1: 0.1,
      nprocCores: 4,
      memPercent: 20,
      diskRootPercent: 30,
      failedUnitCount: 0,
      pendingUpdates: 0,
      fetchedAt: DateTime.now().toUtc(),
      k8s: k8s,
    );

const _healthyK8s = FleetK8sSummary(
  read: true,
  apiReachable: true,
  nodesReady: 3,
  nodesTotal: 3,
);

/// Runs fleet probes against canned stdout, through each probe's parse.
class _Runner {
  _Runner({required this.openShift, this.ocpStdout});

  final bool openShift;
  final String? ocpStdout;
  final ran = <Type>[];

  Future<T> call<T>(Probe<T> probe) async {
    ran.add(probe.runtimeType);
    if (probe is FleetClusterProbe) {
      return probe.parse(_clusterOut(openShift: openShift), '', 0);
    }
    if (probe is FleetWorkloadListProbe) {
      return const WorkloadInventory(rows: []) as T;
    }
    if (probe is FleetOpenShiftProbe) {
      return probe.parse(ocpStdout ?? '', 'Error from server (Forbidden)', 1);
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

/// Cluster read with no OPENSHIFT section: kind unknown.
class _UnknownKindRunner {
  Future<T> call<T>(Probe<T> probe) async {
    if (probe is FleetClusterProbe) {
      return probe.parse(
        '---HOSTNAME---\nb\n---READYZ---\nok\n---NODES---\n{"items":[]}',
        '',
        0,
      );
    }
    if (probe is FleetWorkloadListProbe) {
      return const WorkloadInventory(rows: []) as T;
    }
    throw StateError('unexpected ${probe.runtimeType}');
  }
}

void main() {
  group('FleetOcpSummary', () {
    test('tile line per spec', () {
      expect(
        const FleetOcpSummary(version: '4.17.3', operatorsDegraded: 2).tileLine,
        'OCP 4.17.3 · 2 operators degraded',
      );
      expect(const FleetOcpSummary(version: '4.17.3').tileLine, 'OCP 4.17.3');
      expect(
        const FleetOcpSummary(
          version: '4.17.3',
          operatorsUnavailable: 1,
          poolsDegraded: 1,
          pendingCsrs: 2,
        ).tileLine,
        'OCP 4.17.3 · 1 operator unavailable · 1 pool degraded · 2 CSRs pending',
      );
    });

    test('health: failed vs warning vs healthy', () {
      expect(const FleetOcpSummary(operatorsDegraded: 1).health, HealthStatus.failed);
      expect(const FleetOcpSummary(versionFailing: true).health, HealthStatus.failed);
      expect(const FleetOcpSummary(poolsDegraded: 1).health, HealthStatus.failed);
      expect(const FleetOcpSummary(pendingCsrs: 1).health, HealthStatus.warning);
      expect(const FleetOcpSummary(poolsPaused: 1).health, HealthStatus.warning);
      expect(const FleetOcpSummary().health, HealthStatus.healthy);
    });

    test('survives the fleet cache JSON; old JSON has no ocp', () {
      final s = _healthyK8s.withOcp(
        const FleetOcpSummary(
          version: '4.17.3',
          operatorsDegraded: 2,
          operatorsUnavailable: 1,
          poolsDegraded: 1,
          pendingCsrs: 3,
          versionFailing: true,
          poolsPaused: 1,
        ),
      );
      final round = FleetK8sSummary.decode(s.encode())!;
      expect(round.ocp!.toJson(), s.ocp!.toJson());
      expect(round.nodesTotal, 3);
      final old = FleetK8sSummary.decode(
        '{"read":true,"api":true,"nodesReady":1,"nodesTotal":1,"failed":0,"warn":0}',
      )!;
      expect(old.ocp, isNull);
    });
  });

  group('readFleetK8s (M48 §5)', () {
    test('OpenShift cluster: OpenShift probe runs after the cluster read', () async {
      final run = _Runner(openShift: true, ocpStdout: _ocpOut());
      final s = await readFleetK8s(_oc, run.call);
      expect(run.ran, [
        FleetClusterProbe,
        FleetWorkloadListProbe,
        FleetOpenShiftProbe,
      ]);
      expect(s!.ocp, isNotNull);
      expect(s.ocp!.version, '4.17.3');
      expect(s.ocp!.operatorsDegraded, 1);
      expect(s.ocp!.operatorsUnavailable, 1);
      expect(s.nodes, ['master-0', 'worker-1', 'worker-2']);
    });

    test('feeds the cluster-kind cache only when isOpenShift is known',
        () async {
      final seen = <bool?>[];
      await readFleetK8s(
        _oc,
        _Runner(openShift: true, ocpStdout: _ocpOut()).call,
        onClusterKind: (h) => seen.add(h.isOpenShift),
      );
      await readFleetK8s(
        HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
        _Runner(openShift: false).call,
        onClusterKind: (h) => seen.add(h.isOpenShift),
      );
      expect(seen, [true, false]);

      final unknown = <bool?>[];
      await readFleetK8s(
        _oc,
        _UnknownKindRunner().call,
        onClusterKind: (h) => unknown.add(h.isOpenShift),
      );
      expect(unknown, isEmpty);
    });

    test('a throwing cache callback never breaks the fleet read', () async {
      final s = await readFleetK8s(
        _oc,
        _Runner(openShift: true, ocpStdout: _ocpOut()).call,
        onClusterKind: (_) => throw StateError('disk full'),
      );
      expect(s!.read, isTrue);
      expect(s.ocp, isNotNull);
    });

    test('vanilla cluster: no OpenShift probe, no ocp', () async {
      final run = _Runner(openShift: false);
      final s = await readFleetK8s(
        HostFacts.undiscovered.copyWith(runtimes: const ['kubectl']),
        run.call,
      );
      expect(run.ran, isNot(contains(FleetOpenShiftProbe)));
      expect(s!.ocp, isNull);
      expect(s.read, isTrue);
    });

    test('OpenShift read failing leaves ocp null and keeps the rest', () async {
      final run = _Runner(openShift: true, ocpStdout: 'garbage');
      final s = await readFleetK8s(_oc, run.call);
      expect(run.ran, contains(FleetOpenShiftProbe));
      expect(s!.ocp, isNull);
      expect(s.read, isTrue);
      expect(s.nodesTotal, 3);
    });

    test('FleetOpenShiftProbe throws when no section printed JSON', () {
      expect(
        () => const FleetOpenShiftProbe().parse('---CSR---\nKELOLA_ERR x', '', 1),
        throwsA(isA<K8sReadException>()),
      );
      expect(
        const FleetOpenShiftProbe().parse(_ocpOut(), '', 0).operators,
        hasLength(5),
      );
    });
  });

  group('tile and issues', () {
    test('tile health is the worse of K8s and OCP', () {
      final degraded = _host(
        _healthyK8s.withOcp(
          const FleetOcpSummary(version: '4.17.3', operatorsDegraded: 2),
        ),
      );
      final a = assessFleetHost(degraded);
      expect(a.tileHealth, FleetTileHealth.failed);
      final issue = a.issues.single;
      expect(issue.kind, FleetIssueKind.ocpDegraded);
      expect(issue.meta, 'OCP 4.17.3 · 2 operators degraded');
      expect(issue.isActionable, isTrue);

      final pending = _host(
        _healthyK8s.withOcp(const FleetOcpSummary(version: '4.17.3', pendingCsrs: 2)),
      );
      expect(assessFleetHost(pending).tileHealth, FleetTileHealth.warning);
      expect(assessFleetHost(pending).issues.single.kind, FleetIssueKind.ocpAttention);

      final healthy = _host(
        _healthyK8s.withOcp(const FleetOcpSummary(version: '4.17.3')),
      );
      expect(assessFleetHost(healthy).tileHealth, FleetTileHealth.healthy);
      expect(assessFleetHost(healthy).issues, isEmpty);
    });

    test('ocp cell: version when healthy, short trouble otherwise', () {
      String? cell(FleetOcpSummary o) {
        final m = _host(_healthyK8s.withOcp(o))
            .tileMetrics()
            .where((m) => m.label == 'ocp');
        return m.isEmpty ? null : m.single.value;
      }

      expect(cell(const FleetOcpSummary(version: '4.17.3')), '4.17.3');
      expect(
        cell(const FleetOcpSummary(version: '4.17.3', operatorsDegraded: 2)),
        '2 op deg',
      );
      expect(cell(const FleetOcpSummary(pendingCsrs: 2)), '2 csr');
      expect(
        _host(_healthyK8s).tileMetrics().where((m) => m.label == 'ocp'),
        isEmpty,
      );
    });

    test('a failed OCP cluster names its degraded operators', () {
      final failed = assessFleetHost(
        _host(
          _healthyK8s.withOcp(
            const FleetOcpSummary(version: '4.17.3', operatorsDegraded: 2),
          ),
        ),
      );
      expect(failed.issues.single.meta, 'OCP 4.17.3 · 2 operators degraded');
    });
  });

  testWidgets('fleet tile and issue with an OKD summary read OKD',
      (tester) async {
    final row = _host(
      _healthyK8s.withOcp(
        const FleetOcpSummary(
          version: '4.17.0-okd-scos.0',
          distro: OpenShiftDistro.okd,
          operatorsDegraded: 2,
        ),
      ),
    );
    expect(
      assessFleetHost(row).issues.single.meta,
      'OKD 4.17.0-okd-scos.0 · 2 operators degraded',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 140,
            child: FleetHostTile(
              alias: row.alias,
              status: HealthStatus.failed,
              metrics: [
                for (final m in row.tileMetrics())
                  FleetTileMetricView(label: m.label, value: m.value),
              ],
            ),
          ),
        ),
      ),
    );
    // Cell label names the product; the value is unchanged.
    expect(find.text('okd'), findsOneWidget);
    expect(find.text('ocp'), findsNothing);
    expect(find.text('2 op deg'), findsOneWidget);
  });

  test('FleetOcpSummary.from takes the distro from the version', () {
    final okd = parseOpenShiftHealth(
      '---CLUSTERVERSION---\n'
      '${File('test/fixtures/openshift/okd/clusterversion_scos.json').readAsStringSync()}',
    );
    expect(FleetOcpSummary.from(okd).distro, OpenShiftDistro.okd);
    expect(FleetOcpSummary.from(okd).tileLine, 'OKD 4.17.0-okd-scos.0');
    expect(FleetOcpSummary.from(parseOpenShiftHealth(_ocpOut())).tileLine,
        'OCP 4.17.3 · 1 operator degraded · 1 operator unavailable');
  });

  testWidgets('fleet tile shows the OCP cell', (tester) async {
    final row = _host(
      _healthyK8s.withOcp(
        const FleetOcpSummary(version: '4.17.3', operatorsDegraded: 2),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildKelolaDarkTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 140,
            child: FleetHostTile(
              alias: row.alias,
              status: HealthStatus.failed,
              metrics: [
                for (final m in row.tileMetrics())
                  FleetTileMetricView(label: m.label, value: m.value),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('ocp'), findsOneWidget);
    expect(find.text('2 op deg'), findsOneWidget);
  });

  test('cluster health parse feeds OCP node data without a new call', () {
    final h = parseClusterHealth(_clusterOut(openShift: true));
    expect(h.isOpenShift, isTrue);
    final ocp = parseOpenShiftHealth(_ocpOut()).withNodes(h.nodes);
    expect(ocp.degradedNodes.map((n) => n.name), ['worker-2']);
  });
}
