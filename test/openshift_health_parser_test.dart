import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/design/kelola_theme.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/k8s/cluster_health.dart';
import 'package:kelola/domain/k8s/cluster_health_parser.dart';
import 'package:kelola/domain/k8s/openshift_health.dart';
import 'package:kelola/domain/k8s/openshift_health_parser.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';

String _fixture(String name) =>
    File('test/fixtures/openshift/$name').readAsStringSync();

const _healthyOperator = '''
{"items":[{"metadata":{"name":"dns"},"status":{"versions":[{"name":"operator","version":"4.17.3"}],"conditions":[
{"type":"Available","status":"True"},{"type":"Progressing","status":"False"},{"type":"Degraded","status":"False"}]}}]}''';
const _healthyPool = '''
{"items":[{"metadata":{"name":"master"},"spec":{"paused":false},"status":{"machineCount":1,"readyMachineCount":1,"updatedMachineCount":1,"degradedMachineCount":0,"conditions":[]}}]}''';
const _noCsr = '{"items":[]}';

String _out({
  String? cv,
  String? co,
  String? mcp,
  String? csr,
}) {
  return [
    if (cv != null) ...['---CLUSTERVERSION---', cv],
    if (co != null) ...['---CLUSTEROPERATORS---', co],
    if (mcp != null) ...['---MCP---', mcp],
    if (csr != null) ...['---CSR---', csr],
  ].join('\n');
}

String _healthyOut({String? cv, String? co, String? mcp, String? csr}) => _out(
      cv: cv ?? _fixture('synthetic_clusterversion_healthy.json'),
      co: co ?? _healthyOperator,
      mcp: mcp ?? _healthyPool,
      csr: csr ?? _noCsr,
    );

const _forbidden =
    'KELOLA_ERR Error from server (Forbidden): certificatesigningrequests.certificates.k8s.io is forbidden: User "developer" cannot list resource\n'
    'KELOLA_ERR sudo: a password is required';

void main() {
  group('probe', () {
    test('read-only batch with the four markers, each via kubectlTry', () {
      final cmd = const OpenShiftHealthProbe()
          .command(HostFacts.undiscovered.copyWith(runtimes: const ['oc']));
      for (final m in ['CLUSTERVERSION', 'CLUSTEROPERATORS', 'MCP', 'CSR']) {
        expect(cmd, contains('echo ---$m---'));
      }
      expect(cmd, contains('get clusterversion version --output=json'));
      expect(cmd, contains('get clusteroperators --output=json'));
      expect(cmd, contains('get machineconfigpools --output=json'));
      expect(cmd, contains('get csr --output=json'));
      expect(cmd, contains("sed 's/^/KELOLA_ERR /'"));
      for (final verb in [
        ' adm ',
        ' approve',
        ' patch ',
        ' delete ',
        ' apply ',
        ' debug ',
        ' cordon',
        ' drain',
      ]) {
        expect(cmd, isNot(contains(verb)), reason: verb);
      }
      expect(const OpenShiftHealthProbe().auditTitle, 'Read OpenShift health');
      expect(const OpenShiftHealthProbe().timeout, const Duration(seconds: 30));
      expect(const OpenShiftHealthProbe().needsSudo, isFalse);
    });

    test('no kubectl prints the marker only', () {
      expect(
        const OpenShiftHealthProbe().command(HostFacts.undiscovered),
        'echo ---NO_KUBECTL---',
      );
    });
  });

  group('parser honesty', () {
    test('fixtures parse with no section errors', () {
      final h = parseOpenShiftHealth(
        _out(
          cv: _fixture('synthetic_clusterversion_failing.json'),
          co: _fixture('synthetic_clusteroperators.json'),
          mcp: _fixture('synthetic_machineconfigpools.json'),
          csr: _fixture('synthetic_csr_two_pending.json'),
        ),
      );
      expect(h.sectionErrors, isEmpty);
      expect(h.version!.version, '4.17.3');
      expect(h.version!.channel, 'stable-4.17');
      expect(h.version!.availableUpdates, 2);
      expect(h.version!.overrides, 1);
      expect(h.operators!.map((o) => o.name), [
        'authentication',
        'dns',
        'ingress',
        'machine-config',
        'monitoring',
      ]);
      expect(h.operators!.first.version, '4.17.3');
      expect(h.pools!.length, 4);
      expect(h.csrs!.count, 2);
      expect(h.csrs!.usernames, [
        'system:serviceaccount:openshift-machine-config-operator:node-bootstrapper',
        'system:node:worker-2',
      ]);
    });

    test('junk never throws and reads as unknown, not healthy', () {
      for (final junk in ['', 'garbage', '\x00\x01', '---', '{{{{']) {
        final h = parseOpenShiftHealth(junk);
        expect(h.version, isNull);
        expect(h.operators, isNull);
        expect(h.pools, isNull);
        expect(h.csrs, isNull);
        expect(h.sectionErrors.length, 4);
        expect(h.overall, HealthStatus.unknown);
      }
    });

    test('truncated JSON is a section error, never an empty list', () {
      final full = _fixture('synthetic_clusteroperators.json');
      final h = parseOpenShiftHealth(
        _healthyOut(co: full.substring(0, full.length ~/ 2)),
      );
      expect(h.operators, isNull);
      expect(h.sectionErrors[OcpSection.clusterOperators], 'unreadable output');
      expect(h.version, isNotNull);
      expect(h.overall, HealthStatus.unknown);
    });

    for (final section in OcpSection.values) {
      test('${section.name} missing is its own error', () {
        final h = parseOpenShiftHealth(
          _out(
            cv: section == OcpSection.clusterVersion
                ? null
                : _fixture('synthetic_clusterversion_healthy.json'),
            co: section == OcpSection.clusterOperators ? null : _healthyOperator,
            mcp: section == OcpSection.machineConfigPools ? null : _healthyPool,
            csr: section == OcpSection.csrs ? null : _noCsr,
          ),
        );
        expect(h.sectionErrors.keys, [section]);
        expect(h.overall, HealthStatus.unknown);
      });

      test('${section.name} Forbidden reads "Could not read …: Forbidden"', () {
        final h = parseOpenShiftHealth(
          _healthyOut(
            cv: section == OcpSection.clusterVersion ? _forbidden : null,
            co: section == OcpSection.clusterOperators ? _forbidden : null,
            mcp: section == OcpSection.machineConfigPools ? _forbidden : null,
            csr: section == OcpSection.csrs ? _forbidden : null,
          ),
        );
        expect(h.sectionErrors, {section: 'Forbidden'});
        expect(h.errorFor(section), 'Could not read ${section.what}: Forbidden');
      });
    }

    test('CSR Forbidden copy matches the spec', () {
      final h = parseOpenShiftHealth(_healthyOut(csr: _forbidden));
      expect(h.errorFor(OcpSection.csrs), 'Could not read CSRs: Forbidden');
      expect(h.csrsLabel, 'unknown');
    });

    test('error reasons: Unauthorized, NotFound, first line', () {
      expect(
        ocpErrorReason('KELOLA_ERR error: You must be logged in to the server (Unauthorized)'),
        'Unauthorized',
      );
      expect(
        ocpErrorReason('KELOLA_ERR error: the server doesn\'t have a resource type "machineconfigpools"'),
        'NotFound',
      );
      expect(ocpErrorReason('KELOLA_ERR something odd'), 'something odd');
      expect(ocpErrorReason(''), '');
    });
  });

  group('severity table (M48 §2d)', () {
    OpenShiftHealth parse({String? cv, String? co, String? mcp, String? csr}) =>
        parseOpenShiftHealth(_healthyOut(cv: cv, co: co, mcp: mcp, csr: csr));

    String op(String conds) =>
        '{"items":[{"metadata":{"name":"x"},"status":{"conditions":[$conds]}}]}';
    String pool(String fields, {bool paused = false, String conds = ''}) =>
        '{"items":[{"metadata":{"name":"p"},"spec":{"paused":$paused},"status":{"machineCount":2,"readyMachineCount":2,"updatedMachineCount":2,$fields"conditions":[$conds]}}]}';

    test('baseline healthy', () {
      final h = parse();
      expect(h.findings, isEmpty);
      expect(h.overall, HealthStatus.healthy);
      expect(h.summary, 'Operators, pools and nodes healthy');
    });

    test('ClusterVersion Failing=True is failed', () {
      final h = parse(cv: _fixture('synthetic_clusterversion_failing.json'));
      expect(h.version!.failing, isTrue);
      expect(
        h.findings.where((f) => f.subject == 'ClusterVersion').single.health,
        HealthStatus.failed,
      );
      expect(h.overall, HealthStatus.failed);
    });

    test('ClusterOperator Available=False is failed', () {
      final h = parse(
        co: op('{"type":"Available","status":"False","reason":"Down"},{"type":"Degraded","status":"False"}'),
      );
      expect(h.operatorsUnavailable, 1);
      expect(h.findings.single.health, HealthStatus.failed);
      expect(h.findings.single.message, 'Down');
    });

    test('ClusterOperator Degraded=True is failed', () {
      final h = parse(
        co: op('{"type":"Available","status":"True"},{"type":"Degraded","status":"True","message":"boom"}'),
      );
      expect(h.operatorsDegraded, 1);
      expect(h.findings.single.health, HealthStatus.failed);
      expect(h.summary, '1 operator degraded');
    });

    test('MCP Degraded=True is failed', () {
      final h = parse(
        mcp: pool('', conds: '{"type":"Degraded","status":"True","message":"bad"}'),
      );
      expect(h.findings.single.health, HealthStatus.failed);
      expect(h.findings.single.message, 'bad');
    });

    test('MCP degradedMachineCount > 0 is failed', () {
      final h = parse(mcp: pool('"degradedMachineCount":1,'));
      expect(h.poolsDegraded, 1);
      expect(h.overall, HealthStatus.failed);
    });

    test('node MCD Degraded is failed', () {
      final nodes = parseClusterHealth(
        '---NODES---\n${_fixture('synthetic_nodes.json')}',
      ).nodes;
      final h = parse().withNodes(nodes);
      final f = h.findings.single;
      expect(f.subject, 'node worker-2');
      expect(f.health, HealthStatus.failed);
      expect(h.summary, '1 node degraded');
    });

    test('MCP spec.paused is a warning', () {
      final h = parse(mcp: pool('', paused: true));
      expect(h.findings.single.health, HealthStatus.warning);
      expect(h.findings.single.message, contains('kubelet certificate rotation'));
      expect(h.overall, HealthStatus.warning);
    });

    test('pending CSRs are a warning', () {
      final h = parse(csr: _fixture('synthetic_csr_two_pending.json'));
      expect(h.findings.single.health, HealthStatus.warning);
      expect(h.findings.single.subject, '2 pending CSRs');
      expect(h.csrsLabel, '2 pending');
    });

    test('Progressing, updating pools, update-pending nodes are facts only', () {
      final cv = _fixture('synthetic_clusterversion_failing.json')
          .replaceFirst('"type": "Failing", "status": "True"', '"type": "Failing", "status": "False"');
      final nodes = [
        const ClusterNodeMembership(
          name: 'w',
          ready: true,
          kubeletVersion: '',
          containerRuntime: '',
          mcdState: McdState.working,
          updatePending: true,
        ),
      ];
      final h = parse(
        cv: cv,
        co: op('{"type":"Available","status":"True"},{"type":"Progressing","status":"True"},{"type":"Degraded","status":"False"}'),
        mcp: pool('', conds: '{"type":"Updating","status":"True","message":"rolling"}'),
      ).withNodes(nodes);
      expect(h.version!.progressing, isTrue);
      expect(h.operatorsProgressing, 1);
      expect(h.pools!.single.updating, isTrue);
      expect(h.findings, isEmpty);
      expect(h.overall, HealthStatus.healthy);
    });

    test('availableUpdates and overrides are facts, not findings', () {
      final cv = _fixture('synthetic_clusterversion_failing.json')
          .replaceFirst('"type": "Failing", "status": "True"', '"type": "Failing", "status": "False"');
      final h = parse(cv: cv);
      expect(h.version!.availableUpdates, 2);
      expect(h.version!.overrides, 1);
      expect(h.findings, isEmpty);
    });

    test('Upgradeable=False is ignored', () {
      final h = parse(
        cv: _fixture('synthetic_clusterversion_healthy.json'),
        co: op('{"type":"Available","status":"True"},{"type":"Degraded","status":"False"},{"type":"Upgradeable","status":"False"}'),
      );
      expect(h.findings, isEmpty);
      expect(h.overall, HealthStatus.healthy);
      expect(h.operators!.single.conditions.map((c) => c.type),
          isNot(contains('Upgradeable')));
    });

    test('synthetic operators: counts and filters', () {
      final h = parse(co: _fixture('synthetic_clusteroperators.json'));
      final ops = h.operators!;
      expect(h.operatorsLabel, '3/5 healthy');
      expect(OcpOperatorFilter.all.count(ops), 5);
      expect(OcpOperatorFilter.degraded.count(ops), 1);
      expect(OcpOperatorFilter.unavailable.count(ops), 1);
      expect(OcpOperatorFilter.progressing.count(ops), 1);
      expect(h.summary, '1 operator degraded · 1 operator unavailable');
    });

    test('synthetic pools: mid-rollout, paused, degraded; selector match', () {
      final h = parse(mcp: _fixture('synthetic_machineconfigpools.json'));
      final pools = {for (final p in h.pools!) p.name: p};
      expect(pools['worker']!.updating, isTrue);
      expect(pools['worker']!.meta, '1/3 updated · 2 ready · updating');
      expect(pools['infra']!.paused, isTrue);
      expect(pools['edge']!.isDegraded, isTrue);
      expect(h.poolsLabel, '2/4 updated');
      final nodes = parseClusterHealth(
        '---NODES---\n${_fixture('synthetic_nodes.json')}',
      ).nodes;
      expect(
        nodes.where(pools['worker']!.selects).map((n) => n.name),
        ['worker-1', 'worker-2'],
      );
      expect(nodes.where(pools['master']!.selects).map((n) => n.name), ['master-0']);
      expect(
        const MachineConfigPoolState(name: 'empty').selects(nodes.first),
        isFalse,
      );
    });
  });

  test('worseHealth: known beats unknown; failed beats all', () {
    expect(worseHealth(HealthStatus.healthy, HealthStatus.failed), HealthStatus.failed);
    expect(worseHealth(HealthStatus.warning, HealthStatus.healthy), HealthStatus.warning);
    expect(worseHealth(HealthStatus.healthy, HealthStatus.unknown), HealthStatus.healthy);
    expect(worseHealth(HealthStatus.unknown, HealthStatus.failed), HealthStatus.failed);
    expect(worseHealth(HealthStatus.unknown, HealthStatus.unknown), HealthStatus.unknown);
  });
}
