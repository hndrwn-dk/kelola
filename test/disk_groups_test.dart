import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/disk/disk_snapshot.dart';

void main() {
  test('root stays primary and tmpfs is ephemeral', () {
    const mounts = [
      DiskMount(
        device: '/dev/sda2',
        fsType: 'ext4',
        kibTotal: 100,
        kibUsed: 50,
        usedPercent: 50,
        mounted: '/',
      ),
      DiskMount(
        device: 'tmpfs',
        fsType: 'tmpfs',
        kibTotal: 10,
        kibUsed: 1,
        usedPercent: 10,
        mounted: '/dev/shm',
      ),
      DiskMount(
        device: 'tmpfs',
        fsType: 'tmpfs',
        kibTotal: 4,
        kibUsed: 1,
        usedPercent: 20,
        mounted: '/run/credentials/foo',
      ),
    ];
    final g = groupDiskMounts(mounts);
    expect(g.primary.single.mounted, '/');
    expect(g.ephemeral.map((m) => m.mounted), contains('/dev/shm'));
  });
}
