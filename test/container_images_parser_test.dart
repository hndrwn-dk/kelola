import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/containers/container_images_parser.dart';
import 'package:kelola/domain/probes/container_images_probe.dart';
import 'package:kelola/domain/probes/container_prune_probe.dart';
import 'package:kelola/domain/facts/host_facts.dart';

void main() {
  test('images are sorted by size descending and expose reclaimable bytes', () {
    const raw = '''
---IMAGES---
{"ID":"aaa","Repository":"linuxserver/plex","Tag":"latest","Size":"1.2GB"}
{"ID":"bbb","Repository":"nginx","Tag":"latest","Size":"187MB"}
{"ID":"ccc","Repository":"busybox","Tag":"latest","Size":"4.5MB"}
---DF---
TYPE            TOTAL     ACTIVE    SIZE      RECLAIMABLE
Images          12        8         4.5GB     1.234GB (27%)
Containers      5         3         120MB     80MB
''';
    final inv = const ContainerImagesParser().parse(raw, engine: 'docker');
    expect(inv.images.map((i) => i.repository),
        ['linuxserver/plex', 'nginx', 'busybox']);
    expect(inv.reclaimableBytes, greaterThan(1 << 30));
    expect(inv.reclaimableLabel, contains('1.234GB'));
  });

  test('podman images JSON array also sorts by size', () {
    const raw = '''
---IMAGES---
[{"Id":"a","Names":["postgres:16"],"Size":800000000},{"Id":"b","Names":["alpine:latest"],"Size":8000000}]
---DF---
Images  2  1  808MB  12MB (1%)
''';
    final inv = const ContainerImagesParser().parse(raw, engine: 'podman');
    expect(inv.images.first.repository, contains('postgres'));
    expect(inv.images.first.sizeBytes, greaterThan(inv.images.last.sizeBytes));
  });

  test('images probe is read; prune probe is destructive and never auto-runs', () {
    const list = ContainerImagesProbe(engine: 'docker');
    const prune = ContainerPruneProbe(engine: 'docker');
    expect(list.risk.name, 'read');
    expect(list.command(HostFacts.undiscovered), contains('docker images'));
    expect(list.command(HostFacts.undiscovered), contains('system df'));
    expect(prune.risk.name, 'destructive');
    expect(prune.command(HostFacts.undiscovered), contains('image prune'));
    expect(prune.command(HostFacts.undiscovered), isNot(contains('prune -af')));
  });
}
