import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/containers/docker_ps_parser.dart';
import 'package:kelola/domain/containers/podman_ps_parser.dart';
import 'package:kelola/domain/probes/container_list_probe.dart';
import 'package:kelola/domain/facts/host_facts.dart';

void main() {
  test('docker NDJSON parser reads labels, mapped ports, and health', () {
    const line =
        '{"ID":"abc123","Names":"plex","Image":"linuxserver/plex","State":"running","Status":"Up 12 days (healthy)","Ports":"0.0.0.0:32787->32400/tcp, :::32787->32400/tcp","Labels":"com.docker.compose.project=media,com.docker.compose.service=plex","RunningFor":"12 days ago"}';
    final row = parseDockerNdjson(line).single;
    expect(row.names, 'plex');
    expect(row.image, 'linuxserver/plex');
    expect(row.composeProject, 'media');
    expect(row.publishedPorts, '32787\u219232400');
    expect(row.status.toLowerCase(), contains('healthy'));
    expect(row.engine, 'docker');
  });

  test('podman JSON array parser is separate and handles rootless fields', () {
    const body = '''
[{"Id":"def456","Names":["db"],"Image":"postgres:16","State":"running","Status":"Up 47 hours","ExitCode":0,"Labels":{"com.docker.compose.project":"infra"},"Ports":[{"host_ip":"0.0.0.0","container_port":5432,"host_port":5432,"protocol":"tcp"}]}]
''';
    final row = parsePodmanJson(body).single;
    expect(row.names, 'db');
    expect(row.image, 'postgres:16');
    expect(row.composeProject, 'infra');
    expect(row.publishedPorts, '5432');
    expect(row.engine, 'podman');
    expect(row.running, isTrue);
  });

  test('podman io.podman.compose.project label groups as compose', () {
    const body =
        '[{"Id":"x","Names":["web"],"Image":"nginx","State":"running","Status":"Up","Labels":{"io.podman.compose.project":"webstack"}}]';
    expect(parsePodmanJson(body).single.composeProject, 'webstack');
  });

  test('orchestrator keeps docker NDJSON and podman array on one host', () {
    const raw = '''
---ENGINE---
docker
podman
---PS_DOCKER---
{"ID":"abc","Names":"web","Image":"nginx","State":"running","Status":"Up","Ports":"80/tcp"}
---PS_PODMAN---
[{"Id":"def","Names":["/db"],"Image":"postgres","State":"exited","Status":"Exited (0) 3 days ago","ExitCode":0}]
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.rows, hasLength(2));
    expect(inv.rows.first.engine, 'docker');
    expect(inv.rows.last.engine, 'podman');
    expect(inv.rows.last.exitCode, 0);
  });

  test('exited non-zero captures exit code from Status', () {
    const line =
        '{"ID":"dead","Names":"job","Image":"busybox","State":"exited","Status":"Exited (137) 2 hours ago","Ports":""}';
    final row = parseDockerNdjson(line).single;
    expect(row.exitCode, 137);
    expect(row.running, isFalse);
  });

  test('list probe queries docker and podman separately, podman without sudo first',
      () {
    const probe = ContainerListProbe();
    final cmd = probe.command(HostFacts.undiscovered);
    expect(cmd, contains("docker ps -a --format '{{json .}}'"));
    expect(cmd, contains('podman ps -a --format json'));
    expect(cmd, isNot(contains('elif command -v podman')));
    final podmanIdx = cmd.indexOf('podman ps -a --format json');
    final sudoPodman = cmd.indexOf('sudo -n podman ps');
    expect(podmanIdx, greaterThan(-1));
    if (sudoPodman >= 0) {
      expect(podmanIdx, lessThan(sudoPodman));
    }
  });
}
