import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_list_parser.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';
import 'package:kelola/domain/processes/process_row.dart';

void main() {
  test('parses ps columns', () {
    const raw = '''
    1     0 root      0.0  0.1  1234 Ss   systemd
  420     1 hendr     1.2  0.4  8192 S    sshd
''';
    final rows = const ProcessListParser().parse(raw);
    expect(rows, hasLength(2));
    expect(rows.first.command, 'systemd');
    expect(rows.last.pid, 420);
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
    final rows = const ContainerListParser().parse(docker);
    expect(rows.single.names, 'web');
    expect(rows.single.running, isTrue);

    const podman = '''
---ENGINE---
podman
---PS---
[{"Id":"def","Names":["/db"],"Image":"postgres","State":"exited","Status":"Exited"}]
''';
    final pod = const ContainerListParser().parse(podman);
    expect(pod.single.names, 'db');
    expect(pod.single.running, isFalse);
  });
}
