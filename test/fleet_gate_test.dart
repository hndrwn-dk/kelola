import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/enums.dart';
import 'package:kelola/domain/fleet/fleet_gate.dart';
import 'package:kelola/domain/probes/command_runner_probe.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_prune_probe.dart';
import 'package:kelola/domain/probes/dashboard_probe.dart';
import 'package:kelola/domain/probes/df_pt_probe.dart';
import 'package:kelola/domain/probes/disk_probe.dart';
import 'package:kelola/domain/probes/fleet_health_probe.dart';
import 'package:kelola/domain/probes/host_action_probe.dart';
import 'package:kelola/domain/probes/host_facts_probe.dart';
import 'package:kelola/domain/probes/package_apply_probe.dart';
import 'package:kelola/domain/probes/package_list_probe.dart';
import 'package:kelola/domain/probes/probe.dart';
import 'package:kelola/domain/probes/probe_scope.dart';
import 'package:kelola/domain/probes/process_signal_probe.dart';
import 'package:kelola/domain/probes/unit_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';
import 'package:kelola/domain/units/service_unit.dart';

void main() {
  const container = ContainerRow(
    id: 'abc',
    names: 'web',
    image: 'nginx',
    status: 'Up',
    state: 'running',
    namespace: '',
  );

  final readProbes = <Probe<dynamic>>[
    const DashboardProbe(),
    const DfPtProbe(),
    const DiskProbe(),
    const HostFactsProbe(),
    const PackageListProbe(),
    const FleetHealthProbe(),
  ];

  final nonReadProbes = <Probe<dynamic>>[
    const CommandRunnerProbe('true'),
    const UnitActionProbe(unitName: 'nginx.service', verb: UnitVerb.restart),
    const HostActionProbe(HostVerb.reboot),
    const PackageApplyProbe(
      names: ['curl'],
      securityOnly: false,
      manager: PackageManager.apt,
    ),
    const ContainerPruneProbe(),
    const ContainerActionProbe(row: container, verb: ContainerVerb.restart),
    const ProcessSignalProbe(
      pid: 42,
      signal: ProcessSignal.term,
      commandName: 'sleep',
    ),
  ];

  test('property: host scope never blocks any probe via fleet gate', () {
    for (final p in [...readProbes, ...nonReadProbes]) {
      expect(
        () => assertFleetReadOnly(p, scope: ProbeScope.host),
        returnsNormally,
        reason: p.runtimeType.toString(),
      );
    }
  });

  test('property: fleet scope accepts only RiskLevel.read', () {
    for (final p in readProbes) {
      expect(p.risk, RiskLevel.read, reason: p.runtimeType.toString());
      expect(
        () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
        returnsNormally,
        reason: p.runtimeType.toString(),
      );
    }
    for (final p in nonReadProbes) {
      expect(p.risk, isNot(RiskLevel.read), reason: p.runtimeType.toString());
      expect(
        () => assertFleetReadOnly(p, scope: ProbeScope.fleet),
        throwsA(isA<FleetReadOnlyViolation>()),
        reason: p.runtimeType.toString(),
      );
    }
  });

  test('fleet UI keeps read-only gate and tile probe only', () {
    final ui = File('lib/presentation/screens/fleet_screen.dart')
        .readAsStringSync();
    expect(ui, contains('ProbeScope.fleet'));
    expect(ui, contains('assertFleetReadOnly'));
    expect(ui, contains('FleetHealthProbe'));
    expect(ui, contains('FleetHostTile'));
    expect(ui, isNot(contains('UnitActionProbe')));
    expect(ui, isNot(contains('CommandRunnerProbe')));
    expect(ui, isNot(contains('PackageApplyProbe')));
    expect(ui, isNot(contains('sleep')));
    expect(ui, isNot(contains('MetricsProbe')));
  });
}
