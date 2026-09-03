import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_inspect_parser.dart';

void main() {
  const inspect = '''
---INSPECT---
[{"Id":"abc","Name":"/plex","Config":{"Env":["PATH=/usr/bin","PLEX_TOKEN=super-secret","POSTGRES_PASSWORD=hunter2"],"Image":"linuxserver/plex"},"HostConfig":{"RestartPolicy":{"Name":"unless-stopped","MaximumRetryCount":0},"Binds":null},"Mounts":[{"Type":"bind","Source":"/srv/media","Destination":"/data","Mode":"rw"}],"NetworkSettings":{"Networks":{"media":{"IPAddress":"172.18.0.4"}}},"State":{"Status":"running","ExitCode":0}}]
---STATS---
{"CPUPerc":"1.20%","MemUsage":"120MiB / 2GiB","MemPerc":"5.80%","NetIO":"1.2kB / 0B","BlockIO":"0B / 0B","PIDs":"12","Name":"plex"}
''';

  test('inspect parser extracts mounts, networks, restart policy, stats', () {
    final detail = const ContainerInspectParser().parse(inspect, '', 0);
    expect(detail.name, 'plex');
    expect(detail.restartPolicy, 'unless-stopped');
    expect(detail.mounts, contains('/srv/media \u2192 /data'));
    expect(detail.networks, contains('media'));
    expect(detail.cpuPerc, '1.20%');
    expect(detail.memUsage, '120MiB / 2GiB');
  });

  test('env display redacts secret-shaped values via the M7 table', () {
    final detail = const ContainerInspectParser().parse(inspect, '', 0);
    expect(detail.env, contains('PATH=/usr/bin'));
    expect(detail.env, contains('PLEX_TOKEN=<REDACTED>'));
    expect(detail.env, contains('POSTGRES_PASSWORD=<REDACTED>'));
    expect(detail.env, isNot(contains('super-secret')));
    expect(detail.env, isNot(contains('hunter2')));
  });
}
