import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/container_action_probe.dart';
import 'package:kelola/domain/probes/container_prune_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

void main() {
  const plex = ContainerRow(
    id: 'abc',
    names: 'plex',
    image: 'linuxserver/plex',
    state: 'running',
    status: 'Up',
  );

  test('every action has a human audit title', () {
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.start).auditTitle,
      'Started plex',
    );
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.stop).auditTitle,
      'Stopped plex',
    );
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.restart).auditTitle,
      'Restarted plex',
    );
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.remove).auditTitle,
      'Removed plex',
    );
    expect(const ContainerPruneProbe(engine: 'docker').auditTitle,
        'Pruned unused images');
  });

  test('start and restart are mutate; remove and prune are destructive', () {
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.start).risk,
      RiskLevel.mutate,
    );
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.restart).risk,
      RiskLevel.mutate,
    );
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.remove).risk,
      RiskLevel.destructive,
    );
    expect(const ContainerPruneProbe(engine: 'docker').risk,
        RiskLevel.destructive);
  });

  test('actions go through the named engine binary, never a raw UI shell', () {
    final cmd = ContainerActionProbe(row: plex, verb: ContainerVerb.restart)
        .command(HostFacts.undiscovered);
    expect(cmd, contains('docker'));
    expect(cmd, contains('restart'));
    expect(cmd, contains("'abc'"));
    expect(
      ContainerActionProbe(row: plex, verb: ContainerVerb.remove)
          .command(HostFacts.undiscovered),
      contains('rm'),
    );
  });

  test('podman actions never require sudo in the happy path', () {
    const row = ContainerRow(
      id: 'def',
      names: 'db',
      image: 'postgres',
      state: 'exited',
      status: 'Exited',
      engine: 'podman',
    );
    final cmd = ContainerActionProbe(row: row, verb: ContainerVerb.start)
        .command(HostFacts.undiscovered);
    expect(cmd, contains('podman'));
    expect(cmd.indexOf('podman'), lessThan(cmd.indexOf('sudo -n')));
  });
}
