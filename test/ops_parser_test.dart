import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/processes/process_row.dart';

void main() {
  test('parses ps columns', () {
    const raw = '''
    1     0 root      0.0  0.1  1234  47-00:00:00 Ss   systemd
  420     1 hendr     1.2  0.4  8192     00:02:00 S    sshd
''';
    final rows = const ProcessListParser().parse(raw);
    expect(rows, hasLength(2));
    expect(rows.first.command, 'systemd');
    expect(rows.first.etime, '47-00:00:00');
    expect(rows.last.pid, 420);
    expect(rows.last.etime, '00:02:00');
  });

  test('parses df -PT', () {
    const raw = '''
Filesystem     Type  1024-blocks      Used Available Capacity Mounted on
/dev/sda2      ext4    117440512  57544704  53890048      52% /
tmpfs          tmpfs     1048576         0   1048576       0% /dev/shm
''';
    final mounts = const DiskParser().parseDf(raw);
    expect(mounts.first.mounted, '/');
    expect(mounts.first.usedPercent, 52);
  });

  test('parses docker NDJSON and podman array', () {
    const docker = '''
---ENGINE---
docker
---PS---
{"ID":"abc123","Names":"web","Image":"nginx","State":"running","Status":"Up 3 minutes","Ports":"80/tcp"}
''';
    final rows = const ContainerListParser().parse(docker).rows;
    expect(rows.single.names, 'web');
    expect(rows.single.running, isTrue);

    const podman = '''
---ENGINE---
podman
---PS---
[{"Id":"def","Names":["/db"],"Image":"postgres","State":"exited","Status":"Exited"}]
''';
    final pod = const ContainerListParser().parse(podman).rows;
    expect(pod.single.names, 'db');
    expect(pod.single.running, isFalse);
  });

  test('parses k3s kubectl pod TSV', () {
    const raw = '''
---ENGINE---
k3s
---PODS---
kube-system	coredns-abc	Running	rancher/coredns:1.10
default	nginx	Running	nginx:latest
---PS---
''';
    final rows = const ContainerListParser().parse(raw).rows;
    expect(rows, hasLength(2));
    expect(rows.first.engine, 'k3s');
    expect(rows.first.title, 'kube-system/coredns-abc');
    expect(rows.last.names, 'nginx');
    expect(rows.last.running, isTrue);
  });

  test('docker denied is distinct from an empty engine', () {
    const raw = '''
---ENGINE---
/usr/bin/docker
---PODS---
---PS---
---DOCKER_DENIED---
''';
    final inv = const ContainerListParser().parse(raw);
    expect(inv.dockerDenied, isTrue);
    expect(inv.rows, isEmpty);
  });
}
