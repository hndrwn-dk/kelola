import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/probes/coreos_node_probe.dart';
import 'package:kelola/domain/probes/fleet_k8s_probe.dart';
import 'package:kelola/domain/probes/openshift_health_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/risk/risk_level.dart';

/// M48 §6 architecture pins. OpenShift support is read-only.
void main() {
  test('every M48 probe is risk == read and passes the fleet gate', () {
    const probes = <Probe<dynamic>>[
      OpenShiftHealthProbe(),
      FleetOpenShiftProbe(),
      CoreOsNodeProbe(),
    ];
    for (final p in probes) {
      expect(p.risk, RiskLevel.read, reason: p.runtimeType.toString());
      expect(
        () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
        returnsNormally,
      );
    }
  });

  test('FleetOpenShiftProbe runs exactly the home OpenShift command', () {
    for (final runtimes in [
      ['oc'],
      ['kubectl'],
      ['k3s'],
    ]) {
      final facts = HostFacts.undiscovered.copyWith(runtimes: runtimes);
      expect(
        const FleetOpenShiftProbe().command(facts),
        const OpenShiftHealthProbe().command(facts),
      );
    }
  });

  test('CoreOsNodeProbe never runs oc/kubectl or reads kubelet credentials',
      () {
    for (final access in JournalAccess.values) {
      for (final runtimes in [
        const <String>[],
        ['oc', 'kubectl', 'crictl'],
      ]) {
        final facts = HostFacts.undiscovered.copyWith(
          osId: 'rhcos',
          runtimes: runtimes,
          journalAccess: access,
        );
        final cmd = const CoreOsNodeProbe().command(facts);
        expect(cmd, isNot(contains('oc ')), reason: access.name);
        expect(cmd, isNot(contains('kubectl')), reason: access.name);
        expect(cmd, isNot(contains('/var/lib/kubelet')), reason: access.name);
      }
    }
  });

  test('kubelet journal only when journal access allows', () {
    String cmd(JournalAccess a) => const CoreOsNodeProbe().command(
          HostFacts.undiscovered.copyWith(osId: 'rhcos', journalAccess: a),
        );
    expect(cmd(JournalAccess.plain), contains('journalctl -u kubelet -p warning'));
    expect(cmd(JournalAccess.sudo), contains('sudo -n journalctl -u kubelet'));
    expect(cmd(JournalAccess.denied), isNot(contains('journalctl')));
    expect(cmd(JournalAccess.unknown), isNot(contains('journalctl')));
    expect(cmd(JournalAccess.plain), contains('rpm-ostree status --json'));
    expect(cmd(JournalAccess.plain), contains('systemctl is-active crio kubelet'));
    expect(cmd(JournalAccess.plain), contains('sudo -n crictl ps --output=json'));
  });

  test('no M48 file adds a ProFeature value or a gate call', () {
    for (final path in [
      'lib/domain/k8s/openshift_health.dart',
      'lib/domain/k8s/openshift_health_parser.dart',
      'lib/domain/k8s/coreos_node.dart',
      'lib/domain/probes/openshift_health_probe.dart',
      'lib/domain/probes/coreos_node_probe.dart',
      'lib/presentation/widgets/ocp_operator_sheet.dart',
      'lib/presentation/widgets/coreos_notice_sheet.dart',
      'lib/data/hosts/coreos_ack_store.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('ProFeature')), reason: path);
      expect(src, isNot(contains('isUnlocked')), reason: path);
    }
  });

  // M48 shipped with no schema change. Pinning the literal schemaVersion
  // broke on the next unrelated migration, so pin the M48 files instead:
  // none of them may define a Drift table or touch schemaVersion.
  test('M48 adds no Drift table and no schema change', () {
    for (final path in [
      'lib/domain/k8s/openshift_health.dart',
      'lib/domain/k8s/openshift_health_parser.dart',
      'lib/domain/k8s/coreos_node.dart',
      'lib/domain/probes/openshift_health_probe.dart',
      'lib/domain/probes/coreos_node_probe.dart',
      'lib/presentation/widgets/ocp_operator_sheet.dart',
      'lib/presentation/widgets/coreos_notice_sheet.dart',
      'lib/data/hosts/coreos_ack_store.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('extends Table')), reason: path);
      expect(src, isNot(contains('schemaVersion')), reason: path);
      expect(src, isNot(contains('MigrationStrategy')), reason: path);
    }
  });

  test('M48 sheets avoid AlertDialog and hardcoded colours', () {
    for (final path in [
      'lib/presentation/widgets/ocp_operator_sheet.dart',
      'lib/presentation/widgets/coreos_notice_sheet.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('AlertDialog')), reason: path);
      expect(src, isNot(contains('Color(0x')), reason: path);
      expect(src, contains('KelolaSheet('), reason: path);
    }
  });
}
