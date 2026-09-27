import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/compose_project.dart';
import 'package:kelola/domain/containers/container_row.dart';
import 'package:kelola/domain/facts/host_facts.dart';
import 'package:kelola/domain/probes/compose_action_probe.dart';
import 'package:kelola/domain/risk/risk_level.dart';

const _media = ContainerRow(
  id: 'abc',
  names: 'plex',
  image: 'linuxserver/plex',
  state: 'running',
  status: 'Up',
  composeProject: 'media',
  labels: {
    'com.docker.compose.project': 'media',
    'com.docker.compose.project.working_dir': '/srv/media',
  },
);

void main() {
  test('working dir comes from the compose label, never a guess', () {
    expect(composeWorkingDir(_media.labels), '/srv/media');
    expect(composeWorkingDir(const {}), isEmpty);
    expect(composeProjectReady(_media), isTrue);
    expect(
      composeProjectReady(
        const ContainerRow(
          id: 'x',
          names: 'x',
          image: 'x',
          state: 'running',
          status: 'Up',
          composeProject: 'media',
        ),
      ),
      isFalse,
    );
  });

  test('restart and pull are mutate; down is destructive and quotes paths', () {
    final facts = HostFacts.undiscovered;
    final restart = ComposeActionProbe(
      project: 'media',
      workingDir: '/srv/media',
      verb: ComposeVerb.restart,
      engine: 'docker',
    );
    final down = ComposeActionProbe(
      project: 'media',
      workingDir: '/srv/media',
      verb: ComposeVerb.down,
      engine: 'docker',
    );
    expect(restart.risk, RiskLevel.mutate);
    expect(down.risk, RiskLevel.destructive);
    expect(restart.auditTitle, 'Restarted compose media');
    expect(down.auditTitle, 'Took down compose media');

    final cmd = restart.command(facts);
    expect(cmd, contains('docker compose'));
    expect(cmd, contains("-p 'media'"));
    expect(cmd, contains("--project-directory '/srv/media'"));
    expect(cmd, contains('restart'));
    expect(cmd, isNot(contains('command -v')));
    expect(down.command(facts), contains(' down'));
  });

  test('containers screen wires compose verbs and never guesses a path', () {
    final src = File('lib/presentation/screens/containers_screen.dart')
        .readAsStringSync();
    expect(src, contains('ComposeActionProbe'));
    expect(src, contains('Restart stack'));
    expect(src, contains('no working directory label'));
    expect(src, isNot(contains('command -v')));
    expect(src, isNot(contains('ProbeScope.fleet')));
  });
}
