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
    expect(row.publishedPorts, '0.0.0.0:32787\u219232400, [::]:32787\u219232400');
    expect(row.portBindings.map((p) => p.allInterfaces), [true, true]);
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
    expect(row.publishedPorts, '0.0.0.0:5432');
    expect(row.portBindings.single.allInterfaces, isTrue);
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

  test('rootless empty does not hide a rootful podman container', () {
    const raw = '''
---ENGINE---
podman
---PS_PODMAN---
[]
---PS_PODMAN_ROOT---
[{"Id":"root1","Names":["web"],"Image":"nginx","State":"running","Status":"Up 1 hour"}]
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.rows, hasLength(1));
    expect(inv.rows.single.names, 'web');
    expect(inv.rows.single.engine, 'podman');
    expect(inv.podmanDenied, isFalse);
  });

  test('podman installed but both stores unreachable is denied, not empty success',
      () {
    const raw = '''
---ENGINE---
/usr/bin/podman
---PS_PODMAN---
---PS_PODMAN_ROOT---
---PODMAN_DENIED---
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.rows, isEmpty);
    expect(inv.engines, ['podman']);
    expect(inv.podmanDenied, isTrue);
  });

  test('readable system socket lists rootful containers without sudo', () {
    const raw = '''
---ENGINE---
podman
---PS_PODMAN---
[]
---PS_PODMAN_SOCK---
[{"Id":"sock1","Names":["web"],"Image":"nginx","State":"running","Status":"Up"}]
---PS_PODMAN_ROOT---
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.rows.single.names, 'web');
    expect(inv.podmanSocketDenied, isFalse);
  });

  test('unreadable system socket is the podman-group denial', () {
    const raw = '''
---ENGINE---
podman
---PS_PODMAN---
[]
---PS_PODMAN_SOCK---
---PS_PODMAN_ROOT---
---PODMAN_SOCK_DENIED---
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.rows, isEmpty);
    expect(inv.podmanSocketDenied, isTrue);
    expect(inv.podmanDenied, isFalse);
  });

  test('kubectl jsonpath newline is a shell escape, not a real line break', () {
    final cmd = const ContainerListProbe().command(HostFacts.undiscovered);
    expect(cmd, contains(r'{"\n"}'));
    expect(cmd, isNot(contains('{"\n"}')));
    expect(
      cmd.split('\n').where((line) => line.trimLeft().startsWith('||')),
      isEmpty,
    );
  });

  test('loopback and all-interfaces bindings stay distinct', () {
    const body = '''
[{"Id":"a","Names":["db"],"Image":"postgres","State":"running","Status":"Up","Ports":[
  {"host_ip":"127.0.0.1","container_port":5432,"host_port":55432},
  {"host_ip":"10.1.2.3","container_port":6379,"host_port":56379}
]},
{"Id":"b","Names":["web"],"Image":"nginx","State":"running","Status":"Up","Ports":[
  {"host_ip":"0.0.0.0","container_port":80,"host_port":8443},
  {"host_ip":"127.0.0.1","container_port":3000,"host_port":13000}
]}]
''';
    final rows = parsePodmanJson(body);
    final db = rows.first.portBindings;
    expect(db.map((p) => p.label).toList(), [
      '127.0.0.1:55432\u21925432',
      '10.1.2.3:56379\u21926379',
    ]);
    expect(db.first.loopback, isTrue);
    expect(db.first.allInterfaces, isFalse);
    expect(db.last.loopback, isFalse);
    expect(db.last.allInterfaces, isFalse);
    expect(db.last.bind, '10.1.2.3');
    final web = rows.last.portBindings;
    expect(web.first.allInterfaces, isTrue);
    expect(web.last.loopback, isTrue);
    expect(web.map((p) => p.label).join(', '), rows.last.publishedPorts);
  });

  test('list probe queries user and root podman stores, and sets the runtime dir',
      () {
    const probe = ContainerListProbe();
    final cmd = probe.command(HostFacts.undiscovered);
    expect(cmd, contains("docker ps -a --format '{{json .}}'"));
    expect(cmd, contains('podman ps -a --format json'));
    expect(cmd, contains('XDG_RUNTIME_DIR'));
    expect(cmd, contains('---PS_PODMAN_ROOT---'));
    expect(cmd, contains('---PS_PODMAN_SOCK---'));
    expect(cmd, contains('unix://\$sock'));
    expect(cmd, contains('sock=/run/podman/podman.sock'));
    expect(cmd, contains('---PODMAN_SOCK_DENIED---'));
    expect(cmd, contains('---PODMAN_DENIED---'));
    expect(cmd, isNot(contains('elif command -v podman')));
    expect(cmd, isNot(contains('podman ps -a --format json 2>/dev/null || sudo')));
    final podmanIdx = cmd.indexOf('podman ps -a --format json');
    final sudoPodman = cmd.indexOf('sudo -n podman ps');
    expect(podmanIdx, greaterThan(-1));
    expect(sudoPodman, greaterThan(podmanIdx));
  });
}
